import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/user_model.dart';

/// Abstract definition for the Authentication Repository
abstract class AuthRepository {
  Stream<UserModel?> get authStateChanges;
  Future<void> signInAnonymously();

  /// Signs in as a full editor (persisted locally + Firebase Auth session).
  Future<void> signInAsDemoEditor();
  Future<void> signOut();
}

/// AuthRepository implementation with persistent session storage and
/// automatic Firebase Auth handshake when Firebase is configured.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({this.persistSession = false}) {
    if (persistSession) {
      _restoreSavedSession();
    }
  }

  static const _sessionPrefsKey = 'syncboard_saved_user_session';
  final bool persistSession;

  UserModel? _currentUser;
  final _controller = StreamController<UserModel?>.broadcast();

  Future<void> _restoreSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionPrefsKey);
      if (raw != null && raw.isNotEmpty && _currentUser == null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(decoded);
        _controller.add(_currentUser);
        _ensureFirebaseAuth();
      }
    } catch (_) {}
  }

  Future<void> _persistUser(UserModel? user) async {
    if (!persistSession) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user == null) {
        await prefs.remove(_sessionPrefsKey);
      } else {
        await prefs.setString(_sessionPrefsKey, jsonEncode(user.toJson()));
      }
    } catch (_) {}
  }

  Future<void> _ensureFirebaseAuth() async {
    try {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('[Auth] Firebase Auth optional sign-in skipped: $e');
    }
  }

  // Emit the current value first, then every subsequent change.
  @override
  Stream<UserModel?> get authStateChanges async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  void _set(UserModel? user) {
    _currentUser = user;
    _controller.add(user);
    _persistUser(user);
  }

  @override
  Future<void> signInAnonymously() async {
    await Future.delayed(const Duration(milliseconds: 250));
    await _ensureFirebaseAuth();
    _set(
      const UserModel(
        uid: 'guest-123',
        displayName: 'Guest Viewer',
        isAnonymous: true,
      ),
    );
  }

  @override
  Future<void> signInAsDemoEditor() async {
    await Future.delayed(const Duration(milliseconds: 250));
    await _ensureFirebaseAuth();
    _set(
      const UserModel(
        uid: 'editor-001',
        email: 'demo@boardmate.ai',
        displayName: 'Demo Editor',
      ),
    );
  }

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      if (Firebase.apps.isNotEmpty) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (_) {}
    _set(null);
  }
}

// Provide the repository instance
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return MockAuthRepository(persistSession: true);
});
