import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PeersPage extends StatefulWidget {
  @override
  _PeersPageState createState() => _PeersPageState();
}

class _PeersPageState extends State<PeersPage> {
  final Firestore _db = Firestore.instance;
  String userName = '';
  List<String> activeUsers = [];
  @override
  void initState() {
    _setUserName();
    _registerChannel();
    _subscribeToUsers();
    _subscribeToRecieveCall();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Users'),
      ),
      body: ListView.builder(
        itemCount: activeUsers.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(activeUsers[index]),
          trailing: IconButton(
            icon: Icon(Icons.video_call),
            onPressed: () {
              print('calling => ${activeUsers[index]}');
            },
          ),
        ),
      ),
    );
  }

  void _registerChannel() async {
    _refreshUser();
    Timer.periodic(Duration(seconds: 10), (_) => _refreshUser());
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
      setState(() {
        activeUsers = users;
      });
    });
  }

  void _subscribeToRecieveCall() async {
    await _db.collection('client-signal').document(userName).delete();
    _db
        .collection('client-signal')
        .document(userName)
        .snapshots()
        .listen((event) {});
  }

  void _makeOnCallListener(String userId) {}

  void invite(String peer_id, String media, use_screen) {
    if (this.onStateChange != null) {
      this.onStateChange(SignalingState.CallStateNew);
    }

    _createPeerConnection(peer_id, media, use_screen).then((pc) {
      _peerConnections[peer_id] = pc;
      if (media == 'data') {
        _createDataChannel(peer_id, pc);
      }
      _createOffer(peer_id, pc, media);
    });
  }
}
