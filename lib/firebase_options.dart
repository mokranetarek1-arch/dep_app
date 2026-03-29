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
        return web;
      case TargetPlatform.macOS:
        return web;
      case TargetPlatform.windows:
        return web;
      case TargetPlatform.linux:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBxQ4IstdBzERoOVH6Zc6AxxPX4eKo9Y74',
    appId: '1:534291712626:web:fa136a53cd1d66b72650eb',
    messagingSenderId: '534291712626',
    projectId: 'crmdep',
    authDomain: 'crmdep.firebaseapp.com',
    databaseURL: 'https://crmdep-default-rtdb.firebaseio.com',
    storageBucket: 'crmdep.firebasestorage.app',
    measurementId: 'G-XL3Q4WJWEM',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBKVYMl46FooO881TYLE5LfRcjasKGS4y4',
    appId: '1:534291712626:android:975161790a9589132650eb',
    messagingSenderId: '534291712626',
    projectId: 'crmdep',
    databaseURL: 'https://crmdep-default-rtdb.firebaseio.com',
    storageBucket: 'crmdep.firebasestorage.app',
  );
}
