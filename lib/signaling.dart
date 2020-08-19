import 'dart:async';
import 'package:flutter_peer_example_firebase/firestore_handler.dart';
import 'package:flutter_webrtc/webrtc.dart';

enum SignalingState {
  CallStateNew,
  CallStateRinging,
  CallStateInvite,
  CallStateConnected,
  CallStateBye,
  ConnectionOpen,
  ConnectionClosed,
  ConnectionError,
}

/*
 * callbacks for Signaling API.
 */
typedef void SignalingStateCallback(SignalingState state);
typedef void StreamStateCallback(MediaStream stream);
typedef void OtherEventCallback(dynamic event);
typedef void DataChannelMessageCallback(
    RTCDataChannel dc, RTCDataChannelMessage data);
typedef void DataChannelCallback(RTCDataChannel dc);

class Signaling {
  String _selfId;
  FirestoreHandler _fbHandler;
  String _sessionId;
  Map<String, RTCPeerConnection> _peerConnections =
      new Map<String, RTCPeerConnection>();
  Map<String, RTCDataChannel> _dataChannels = new Map<String, RTCDataChannel>();
  var _remoteCandidates = [];

  MediaStream _localStream;
  List<MediaStream> _remoteStreams;
  SignalingStateCallback onStateChange;
  StreamStateCallback onLocalStream;
  StreamStateCallback onAddRemoteStream;
  StreamStateCallback onRemoveRemoteStream;
  OtherEventCallback onPeersUpdate;
  DataChannelMessageCallback onDataChannelMessage;
  DataChannelCallback onDataChannel;

  Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'url': 'stun:stun.l.google.com:19302'},
      /*
       * turn server configuration example.
      {
        'url': 'turn:123.45.67.89:3478',
        'username': 'change_to_real_user',
        'credential': 'change_to_real_secret'
      },
       */
    ]
  };

  final Map<String, dynamic> _config = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': true,
    },
    'optional': [],
  };

  Signaling(this._selfId);

  close() {
    if (_localStream != null) {
      _localStream.dispose();
      _localStream = null;
    }

    _peerConnections.forEach((key, pc) {
      pc.close();
    });
  }

  void switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  void invite(String peerId) {
    this._sessionId = this._selfId + '-' + peerId;

    if (this.onStateChange != null) {
      this.onStateChange(SignalingState.CallStateNew);
    }

    _createPeerConnection(peerId).then((pc) {
      _peerConnections[peerId] = pc;
      _createOffer(peerId, pc);
    });
  }

  void bye() {
    if (this._sessionId == null) return;
    final ids = this._sessionId.split('-');
    if (ids.length != 2) return;
    _send('bye', ids.first, {
      'session_id': this._sessionId,
      'from': ids.first,
      'to': ids.last,
    });
    _send('bye', ids.last, {
      'session_id': this._sessionId,
      'from': ids.last,
      'to': ids.first,
    });

    // ids.forEach((id) {
    //   _send('bye', id, {
    //     'session_id': this._sessionId,
    //     'from': this._selfId,
    //   });
    // });
  }

  void onMessage(message) async {
    Map<String, dynamic> mapData = message;
    var data = mapData['data'];
    print(data);

    switch (mapData['type']) {
      case 'peers':
        {
          List<dynamic> peers = data;
          if (this.onPeersUpdate != null) {
            Map<String, dynamic> event = new Map<String, dynamic>();
            event['self'] = _selfId;
            event['peers'] = peers;
            this.onPeersUpdate(event);
          }
        }
        break;
      case 'offer':
        {
          var senderId = data['from'];
          var description = data['description'];
          var sessionId = data['session_id'];
          this._sessionId = sessionId;

          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateNew);
          }

          var pc = await _createPeerConnection(senderId);
          _peerConnections[senderId] = pc;
          await pc.setRemoteDescription(new RTCSessionDescription(
              description['sdp'], description['type']));
          await _createAnswer(senderId, pc);
          if (this._remoteCandidates.length > 0) {
            _remoteCandidates.forEach((candidate) async {
              await pc.addCandidate(candidate);
            });
            _remoteCandidates.clear();
          }
        }
        break;
      case 'answer':
        {
          var id = data['from'];
          var description = data['description'];

          var pc = _peerConnections[id];
          if (pc != null) {
            await pc.setRemoteDescription(new RTCSessionDescription(
                description['sdp'], description['type']));
          }
        }
        break;
      case 'candidate':
        {
          var id = data['from'];
          var candidateMap = data['candidate'];
          var pc = _peerConnections[id];
          RTCIceCandidate candidate = new RTCIceCandidate(
              candidateMap['candidate'],
              candidateMap['sdpMid'],
              candidateMap['sdpMLineIndex']);
          if (pc != null) {
            await pc.addCandidate(candidate);
          } else {
            _remoteCandidates.add(candidate);
          }
        }
        break;
      case 'leave':
        {
          var id = data;
          var pc = _peerConnections.remove(id);
          _dataChannels.remove(id);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          if (pc != null) {
            pc.close();
          }
          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'bye':
        {
          var to = data['to'];
          var sessionId = data['session_id'];
          print('bye: ' + sessionId);

          if (_localStream != null) {
            _localStream.dispose();
            _localStream = null;
          }

          var pc = _peerConnections[to];
          if (pc != null) {
            pc.close();
            _peerConnections.remove(to);
          }

          var dc = _dataChannels[to];
          if (dc != null) {
            dc.close();
            _dataChannels.remove(to);
          }

          this._sessionId = null;
          if (this.onStateChange != null) {
            this.onStateChange(SignalingState.CallStateBye);
          }
        }
        break;
      case 'keepalive':
        {
          print('keepalive response!');
        }
        break;
      default:
        break;
    }
  }

  void connect() async {
    _fbHandler = FirestoreHandler();
    _fbHandler.onOpen = () {
      print('onOpen');
      this?.onStateChange(SignalingState.ConnectionOpen);
      // Subscribe user to active users

      _fbHandler.subscribeUser(_selfId);
    };

    _fbHandler.onMessage = (message) {
      print('Received data: ' + message.toString());
      this.onMessage(message);
    };

    _fbHandler.onClose = (int code, String reason) {
      print('Closed by server [$code => $reason]!');
      if (this.onStateChange != null) {
        this.onStateChange(SignalingState.ConnectionClosed);
      }
    };

    await _fbHandler.connect(_selfId);
  }

  Future<MediaStream> createStream() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth':
              '640', // Provide your own width, height and frame rate here
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    MediaStream stream = await navigator.getUserMedia(mediaConstraints);
    if (this.onLocalStream != null) {
      this.onLocalStream(stream);
    }
    return stream;
  }

  Future<RTCPeerConnection> _createPeerConnection(peerId) async {
    _localStream = await createStream();
    RTCPeerConnection pc = await createPeerConnection(_iceServers, _config);
    pc.addStream(_localStream);
    pc.onIceCandidate = (candidate) {
      _send('candidate', peerId, {
        'to': peerId,
        'from': _selfId,
        'candidate': {
          'sdpMLineIndex': candidate.sdpMlineIndex,
          'sdpMid': candidate.sdpMid,
          'candidate': candidate.candidate,
        },
        'session_id': this._sessionId,
      });
    };

    pc.onIceConnectionState = (state) {};

    pc.onAddStream = (stream) {
      if (this.onAddRemoteStream != null) this.onAddRemoteStream(stream);
    };

    pc.onRemoveStream = (stream) {
      if (this.onRemoveRemoteStream != null) this.onRemoveRemoteStream(stream);
      _remoteStreams.removeWhere((it) {
        return (it.id == stream.id);
      });
    };

    pc.onDataChannel = (channel) {
      _addDataChannel(peerId, channel);
    };

    return pc;
  }

  _addDataChannel(id, RTCDataChannel channel) {
    channel.onDataChannelState = (e) {};
    channel.onMessage = (RTCDataChannelMessage data) {
      if (this.onDataChannelMessage != null)
        this.onDataChannelMessage(channel, data);
    };
    _dataChannels[id] = channel;

    if (this.onDataChannel != null) this.onDataChannel(channel);
  }

  _createOffer(String peerId, RTCPeerConnection pc) async {
    try {
      RTCSessionDescription s = await pc.createOffer(_constraints);
      pc.setLocalDescription(s);
      _send('offer', peerId, {
        'to': peerId,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
        'media': 'video',
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _createAnswer(String senderId, RTCPeerConnection pc) async {
    try {
      RTCSessionDescription s = await pc.createAnswer(_constraints);
      pc.setLocalDescription(s);
      _send('answer', senderId, {
        'to': senderId,
        'from': _selfId,
        'description': {'sdp': s.sdp, 'type': s.type},
        'session_id': this._sessionId,
      });
    } catch (e) {
      print(e.toString());
    }
  }

  _send(String event, String peerId, data) {
    var request = new Map<String, dynamic>();
    request["type"] = event;
    request["data"] = data;
    _fbHandler.send(peerId, request);
  }
}
