import 'dart:async';

import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

class FakeSpectrumAuthService implements SpectrumAuthService {
  FakeSpectrumAuthService({SpectrumUser? initialUser}) {
    _snapshot = SpectrumAuthSnapshot(
      state: initialUser == null
          ? SpectrumAuthState.signedOut
          : SpectrumAuthState.signedIn,
      user: initialUser,
    );
  }

  final StreamController<SpectrumAuthSnapshot> _controller =
      StreamController<SpectrumAuthSnapshot>.broadcast();
  SpectrumAuthSnapshot _snapshot = const SpectrumAuthSnapshot(
    state: SpectrumAuthState.signedOut,
  );

  int initializeCalls = 0;
  int signInCalls = 0;
  int signOutCalls = 0;

  SpectrumUser nextSignInUser = const SpectrumUser(
    uid: 'test-uid',
    displayName: 'Test User',
    email: 'test@example.com',
  );

  @override
  Stream<SpectrumAuthSnapshot> get snapshotStream => _controller.stream;

  @override
  SpectrumAuthSnapshot get snapshot => _snapshot;

  @override
  SpectrumUser? get currentUser => _snapshot.user;

  String? fakeIdToken;

  @override
  Future<String?> idToken() async => fakeIdToken;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> signIn() async {
    signInCalls++;
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: nextSignInUser,
      ),
    );
  }

  final List<String> displayNameUpdates = [];

  @override
  Future<void> updateDisplayName(String displayName) async {
    displayNameUpdates.add(displayName);
    final user = _snapshot.user;
    if (user == null) throw StateError('No user is signed in.');
    _emit(
      SpectrumAuthSnapshot(
        state: SpectrumAuthState.signedIn,
        user: SpectrumUser(
          uid: user.uid,
          displayName: displayName,
          email: user.email,
          photoUrl: user.photoUrl,
        ),
      ),
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _emit(const SpectrumAuthSnapshot(state: SpectrumAuthState.signedOut));
  }

  void emit(SpectrumAuthSnapshot next) => _emit(next);

  void _emit(SpectrumAuthSnapshot next) {
    _snapshot = next;
    _controller.add(next);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
