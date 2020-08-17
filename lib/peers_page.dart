import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_peer_example_firebase/signaling.dart';
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
  Signaling _signaling;
  var _selfId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  @override
  void initState() {
    initRenderers();
    _setUserName();
    _subscribeToUsers();
    // _subscribeToRecieveCall();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${userName ?? 'Connection...'}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _hangUp,
        child: Icon(
          Icons.clear,
        ),
      ),
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
              return Container(
                child: Stack(children: <Widget>[
                  Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 0.0,
                      bottom: 0.0,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        child: RTCVideoView(_remoteRenderer),
                        decoration: BoxDecoration(color: Colors.black54),
                      )),
                  Positioned(
                    left: 20.0,
                    top: 20.0,
                    child: Container(
                      width: orientation == Orientation.portrait ? 90.0 : 120.0,
                      height:
                          orientation == Orientation.portrait ? 120.0 : 90.0,
                      child: RTCVideoView(_localRenderer),
                      decoration: BoxDecoration(color: Colors.black54),
                    ),
                  ),
                ]),
              );
            })
          : ListView.builder(
              itemCount: activeUsers.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(activeUsers[index]),
                trailing: IconButton(
                  icon: Icon(Icons.video_call),
                  onPressed: () {
                    print('calling => ${activeUsers[index]}');
                    _invitePeer(activeUsers[index]);
                    // _makeOnCallListener(activeUsers[index]);
                  },
                ),
              ),
            ),
    );
  }

  @override
  deactivate() {
    super.deactivate();
    if (_signaling != null) _signaling.close();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _setUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var userId = prefs.getString('userId');

    if (userId == null) {
      final rand = Random();
      userId = 'USER${rand.nextInt(1000)}';
      await prefs.setString('userId', userId);
    }

    setState(() {
      userName = userId;
    });
    _connect(userId);
    // _subscribeToRecieveCall();
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling.bye();
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

  _invitePeer(peerId) async {
    if (_signaling != null && peerId != _selfId) {
      _signaling.invite(peerId);
    }
  }

  void _connect(String userId) async {
    if (_signaling == null) {
      _signaling = Signaling(userId);

      _signaling.onStateChange = (SignalingState state) {
        switch (state) {
          case SignalingState.CallStateNew:
            this.setState(() {
              _inCalling = true;
            });
            break;
          case SignalingState.CallStateBye:
            this.setState(() {
              _localRenderer.srcObject = null;
              _remoteRenderer.srcObject = null;
              _inCalling = false;
            });
            break;
          case SignalingState.CallStateInvite:
          case SignalingState.CallStateConnected:
          case SignalingState.CallStateRinging:
          case SignalingState.ConnectionClosed:
          case SignalingState.ConnectionError:
          case SignalingState.ConnectionOpen:
            break;
        }
      };

      _signaling.onPeersUpdate = ((event) {
        this.setState(() {
          _selfId = event['self'];
          // _peers = event['peers'];
        });
      });

      _signaling.onLocalStream = ((stream) {
        _localRenderer.srcObject = stream;
      });

      _signaling.onAddRemoteStream = ((stream) {
        _remoteRenderer.srcObject = stream;
      });

      _signaling.onRemoveRemoteStream = ((stream) {
        _remoteRenderer.srcObject = null;
      });
      _signaling.connect();
    }
  }
}
