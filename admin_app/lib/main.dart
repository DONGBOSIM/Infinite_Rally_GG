import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화 (google-services.json 미등록 시에도 로컬 앱이 정상 작동하도록 예외 방어)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // ignore: avoid_print
    print('Firebase 초기화 대기 (설정 파일 필요): $e');
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

