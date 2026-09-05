// ignore_for_file: invalid_use_of_protected_member

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/spectrum_auth_service.dart';

void main() {
  test('popup-blocked falls back to redirect', () {
    expect(
      isPopupBlockedAuthError(FirebaseAuthException(code: 'popup-blocked')),
      isTrue,
    );
  });

  test('popup-blocked-by-user falls back to redirect', () {
    expect(
      isPopupBlockedAuthError(
        FirebaseAuthException(code: 'popup-blocked-by-user'),
      ),
      isTrue,
    );
  });

  test('cancelled-popup-request falls back to redirect', () {
    expect(
      isPopupBlockedAuthError(
        FirebaseAuthException(code: 'cancelled-popup-request'),
      ),
      isTrue,
    );
  });

  test(
    'operation-not-supported-in-this-environment falls back to redirect',
    () {
      expect(
        isPopupBlockedAuthError(
          FirebaseAuthException(
            code: 'operation-not-supported-in-this-environment',
          ),
        ),
        isTrue,
      );
    },
  );

  test('popup-closed-by-user does not fall back to redirect', () {
    expect(
      isPopupBlockedAuthError(
        FirebaseAuthException(code: 'popup-closed-by-user'),
      ),
      isFalse,
    );
  });

  test('network-request-failed does not fall back to redirect', () {
    expect(
      isPopupBlockedAuthError(
        FirebaseAuthException(code: 'network-request-failed'),
      ),
      isFalse,
    );
  });

  test('unauthorized-domain does not fall back to redirect', () {
    expect(
      isPopupBlockedAuthError(
        FirebaseAuthException(code: 'unauthorized-domain'),
      ),
      isFalse,
    );
  });

  test('a non-FirebaseAuthException does not fall back to redirect', () {
    expect(isPopupBlockedAuthError(StateError('boom')), isFalse);
  });

  group('isPopupPersistenceAuthError', () {
    test('the Safari IndexedDB persistence failure falls back', () {
      expect(
        isPopupPersistenceAuthError(
          FirebaseAuthException(
            code: 'unknown',
            message: 'Database is closing/hidden',
          ),
        ),
        isTrue,
      );
    });

    test('matches however the interop layer wraps the message', () {
      expect(
        isPopupPersistenceAuthError(StateError('Database is closing/hidden')),
        isTrue,
      );
    });

    test('an unrelated error does not fall back', () {
      expect(
        isPopupPersistenceAuthError(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        isFalse,
      );
      expect(isPopupPersistenceAuthError(StateError('boom')), isFalse);
    });
  });
}
