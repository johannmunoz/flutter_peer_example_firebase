import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PeersPage extends StatefulWidget {
  @override
  _PeersPageState createState() => _PeersPageState();
}

class _PeersPageState extends State<PeersPage> {
  final Firestore _db = Firestore.instance;
  String userName = '';
  List<String> activeUsers = [];
  RTCPeerConnection pc;
  MediaStream _localStream;

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
  @override
  void initState() {
    _setUserName();
    _registerChannel();
    _subscribeToUsers();
    // _subscribeToRecieveCall();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Users'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          pc.close();
          _localStream.dispose();
        },
        child: Icon(
          Icons.clear,
        ),
      ),
      body: ListView.builder(
        itemCount: activeUsers.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(activeUsers[index]),
          trailing: IconButton(
            icon: Icon(Icons.video_call),
            onPressed: () {
              print('calling => ${activeUsers[index]}');
              _makeOnCallListener(activeUsers[index]);
            },
          ),
        ),
      ),
    );
  }

  void _registerChannel() async {
    _refreshUser();
    Timer.periodic(Duration(seconds: 60), (_) => _refreshUser());
  }

  _setUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('userId');

    if (userId == null) {
      final rand = Random();
      userId = 'USER-${rand.nextInt(1000)}';
      await prefs.setString('userId', userId);
    }

    setState(() {
      userName = userId;
    });
    _subscribeToRecieveCall();
  }

  _refreshUser() async {
    if (userName.isNotEmpty) {
      await _db.collection('active-users').document(userName).setData(
        {
          'lastActive': Timestamp.fromDate(
            DateTime.now(),
          ),
        },
      );
    }
  }

  void _subscribeToUsers() {
    _db.collection('active-users').snapshots().listen((event) {
      final users = event.documents.map((e) => e.documentID).toList();
      users.removeWhere((u) => u == userName);
      setState(() {
        activeUsers = users;
      });
    });
  }

  void _subscribeToRecieveCall() async {
    if (userName == null || userName.isEmpty) return;
    final doc = await _db.collection('client-signal').document(userName).get();

    if (doc.exists) {
      await _db.collection('client-signal').document(userName).delete();
    }
    _db.collection('client-signal').document(userName).snapshots().listen(
      (event) {
        final data = event.data;
        print(data);
      },
    );
  }

  void _makeOnCallListener(String userId) async {
    _localStream = await createStream();
    pc = await createPeerConnection(_iceServers, _config);
    pc.addStream(_localStream);
    pc.onSignalingState = (val) {
      print('val: $val');
    };
    pc.onIceGatheringState = (val) {
      print('val: $val');
    };
    pc.onIceConnectionState = (val) {
      print('val: $val');
    };
    pc.onAddStream = (val) {
      print('val: $val');
    };
    pc.onRemoveStream = (val) {
      print('val: $val');
    };
    pc.onDataChannel = (val) {
      print('val: $val');
    };
    pc.onRenegotiationNeeded = () {
      print('onRenegotiationNeeded');
    };
    pc.onIceCandidate = (candidate) {
      print('candidate: $candidate');
      _sendSignal(candidate, userId);
    };
    RTCSessionDescription rtcSession = await pc.createOffer(_constraints);
    pc.setLocalDescription(rtcSession);
    // pc.createDataChannel(label, dataChannelDict)

    print('rtc session: $rtcSession');
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

    return stream;
  }

  _sendSignal(RTCIceCandidate signalObj, String userId) {
    try {
      _db.collection('client-signal').document(userId).setData(
        {'data': signalObj.toMap(), 'senderId': userName},
      );
    } catch (e) {
      print(e);
    }
  }

  // void invite(String peer_id, String media, use_screen) {
  //   if (this.onStateChange != null) {
  //     this.onStateChange(SignalingState.CallStateNew);
  //   }

  //   _createPeerConnection(peer_id, media, use_screen).then((pc) {
  //     _peerConnections[peer_id] = pc;
  //     if (media == 'data') {
  //       _createDataChannel(peer_id, pc);
  //     }
  //     _createOffer(peer_id, pc, media);
  //   });
  // }
}
