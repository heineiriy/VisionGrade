import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PresenceService {
  static Timer? _heartbeat;
  static DocumentReference<Map<String, dynamic>>? _userDocument;

  static Future<void> start({
    required DocumentReference<Map<String, dynamic>> userDocument,
    required String role,
  }) async {
    _heartbeat?.cancel();
    _userDocument = userDocument;
    await _writePresence(role: role, isOnline: true);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _writePresence(role: role, isOnline: true),
    );
  }

  static Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    final document = _userDocument;
    _userDocument = null;
    if (document == null) return;
    try {
      await document.update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // The session may already be signed out or the document may be gone.
    }
  }

  static Future<void> _writePresence({
    required String role,
    required bool isOnline,
  }) async {
    final document = _userDocument;
    if (document == null) return;
    try {
      await document.set({
        'role': role,
        'authUid': FirebaseAuth.instance.currentUser?.uid,
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Presence must never interrupt the user's session.
    }
  }
}
