// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCgatjO0H0C7pl3Lh0_tfcbFbDV-Xru7yg',
    appId: '1:568915292867:web:c00f045cbc27452aeaa876',
    messagingSenderId: '568915292867',
    projectId: 'frcspectrumstrategy',
    authDomain: 'frcspectrumstrategy.firebaseapp.com',
    storageBucket: 'frcspectrumstrategy.firebasestorage.app',
    measurementId: 'G-3S04VKHKC1',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCkUCucmbxvThSr22OEhjJlUMNIdTdzDXk',
    appId: '1:568915292867:android:f6a2bc0ab029850eeaa876',
    messagingSenderId: '568915292867',
    projectId: 'frcspectrumstrategy',
    storageBucket: 'frcspectrumstrategy.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDWmWrNxEPs6p-PKW2VTYld8Ji55sjGK6k',
    appId: '1:568915292867:ios:5b0fb060195a40d1eaa876',
    messagingSenderId: '568915292867',
    projectId: 'frcspectrumstrategy',
    storageBucket: 'frcspectrumstrategy.firebasestorage.app',
    iosClientId: '568915292867-7jgv1ju796pljr3bei3p6ifhmkohtavi.apps.googleusercontent.com',
    iosBundleId: 'org.spectrum3847.spectrumstrategy',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDWmWrNxEPs6p-PKW2VTYld8Ji55sjGK6k',
    appId: '1:568915292867:ios:5b0fb060195a40d1eaa876',
    messagingSenderId: '568915292867',
    projectId: 'frcspectrumstrategy',
    storageBucket: 'frcspectrumstrategy.firebasestorage.app',
    iosClientId: '568915292867-7jgv1ju796pljr3bei3p6ifhmkohtavi.apps.googleusercontent.com',
    iosBundleId: 'org.spectrum3847.spectrumstrategy',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCgatjO0H0C7pl3Lh0_tfcbFbDV-Xru7yg',
    appId: '1:568915292867:web:c9260180c61561fdeaa876',
    messagingSenderId: '568915292867',
    projectId: 'frcspectrumstrategy',
    authDomain: 'frcspectrumstrategy.firebaseapp.com',
    storageBucket: 'frcspectrumstrategy.firebasestorage.app',
    measurementId: 'G-Y6PRF7F8TK',
  );
}
