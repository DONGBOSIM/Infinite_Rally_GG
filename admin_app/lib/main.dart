import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 실시간 초기화 (FirebaseOptions 직접 주입)
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyBVyqITPF8B3Qx1lMxY9D8Xv2woArylXRw",
        appId: "1:657291415795:android:3cf82c53d6227f0d4ca786",
        messagingSenderId: "657291415795",
        projectId: "infinite-rally-gg",
        storageBucket: "infinite-rally-gg.firebasestorage.app",
      ),
    );
  } catch (e) {
    // ignore: avoid_print
    print('Firebase 초기화 결과: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const InfiniteRallyAdminApp(),
    ),
  );
}

class InfiniteRallyAdminApp extends StatelessWidget {
  const InfiniteRallyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '무한랠리 관리자',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          primary: Colors.indigo.shade700,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
