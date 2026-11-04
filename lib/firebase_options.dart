import 'package:firebase_core/firebase_core.dart';

// Firebase web config (Firebase console → Project settings → Your apps → Web app).
// These values are not secrets; access is enforced by firestore.rules.
const firebaseOptions = FirebaseOptions(
  apiKey: 'REPLACE_ME',
  authDomain: 'REPLACE_ME.firebaseapp.com',
  projectId: 'REPLACE_ME',
  storageBucket: 'REPLACE_ME.firebasestorage.app',
  messagingSenderId: 'REPLACE_ME',
  appId: 'REPLACE_ME',
);
