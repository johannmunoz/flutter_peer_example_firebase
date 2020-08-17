import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef void OnMessageCallback(dynamic msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class FirestoreHandler {
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;
  final Firestore _db = Firestore.instance;

  connect(String userId) async {
    try {
      this?.onOpen();
      _db.collection('client-signal').document(userId).snapshots().listen(
        (event) {
          final data = event.data;
          if (data == null) return;
          this?.onMessage(data);
          print(data);
        },
      );
    } catch (e) {
      this.onClose(500, e.toString());
    }
  }

  send(String peerId, Map<String, dynamic> data) {
    try {
      _db.collection('client-signal').document(peerId).setData(data);
    } catch (e) {
      print(e);
    }
    print('send: $data');
  }

  subscribeUser(String userId) {
    _refreshUser(userId);
    Timer.periodic(Duration(seconds: 60), (_) => _refreshUser(userId));
  }

  _refreshUser(String userId) async {
    if (userId.isNotEmpty) {
      await _db.collection('active-users').document(userId).setData(
        {
          'lastActive': Timestamp.fromDate(
            DateTime.now(),
          ),
        },
      );
    }
  }
}
