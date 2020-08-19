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
  List<Map<String, dynamic>> activeUsers = [];
  Signaling _signaling;
  String _selfId;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  @override
  void initState() {
    initRenderers();
    _setUserName();
    _subscribeToUsers();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_selfId ?? 'Connection...'}'),
      ),
      floatingActionButton: _inCalling
          ? FloatingActionButton(
              onPressed: _hangUp,
              child: Icon(
                Icons.clear,
              ),
            )
          : Container(),
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
              return Container(
                child: Stack(
                  children: <Widget>[
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
                      ),
                    ),
                    Positioned(
                      left: 20.0,
                      top: 20.0,
                      child: Container(
                        width:
                            orientation == Orientation.portrait ? 90.0 : 120.0,
                        height:
                            orientation == Orientation.portrait ? 120.0 : 90.0,
                        child: RTCVideoView(_localRenderer),
                        decoration: BoxDecoration(color: Colors.black54),
                      ),
                    ),
                  ],
                ),
              );
            })
          : ListView.builder(
              itemCount: activeUsers.length,
              itemBuilder: (context, index) {
                final peerId = activeUsers[index]['id'];
                final lastActive = activeUsers[index]['lastActive'];
                return ListTile(
                  title: Text(peerId),
                  subtitle: Text(lastActive.toString()),
                  trailing: IconButton(
                    icon: Icon(Icons.video_call),
                    onPressed: () {
                      print('calling => $peerId');
                      _invitePeer(peerId);
                    },
                  ),
                );
              },
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
      _selfId = userId;
    });
    _connect(userId);
  }

  _hangUp() {
    if (_signaling != null) {
      _signaling.bye();
    }
  }

  void _subscribeToUsers() {
    _db.collection('active-users').snapshots().listen((event) {
      final List<Map<String, dynamic>> users = event.documents.map((d) {
        if (d.data != null || d.data['lastActive'] != null) {
          final user = Map<String, dynamic>();
          final Timestamp timestamp = d.data['lastActive'];
          final DateTime dateBefore =
              DateTime.now().subtract(Duration(minutes: 2));
          final DateTime date = DateTime.fromMillisecondsSinceEpoch(
              timestamp.millisecondsSinceEpoch);
          if (date.isAfter(dateBefore)) {
            user['id'] = d.documentID;
            user['lastActive'] = DateTime.fromMillisecondsSinceEpoch(
                timestamp.millisecondsSinceEpoch);

            return user;
          }
        }
      }).toList();
      users.removeWhere((u) => u == null);
      users.removeWhere((u) => u['id'] == _selfId);
      users.removeWhere((u) => u['lastActive'] == _selfId);
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
