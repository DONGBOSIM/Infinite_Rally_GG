import 'package:flutter/material.dart';
import 'members_tab.dart';
import 'match_tab.dart';
import 'qr_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    MembersTab(),
    MatchTab(),
    QrTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        selectedItemColor: isDark ? Colors.blue.shade300 : Colors.indigo.shade800,
        unselectedItemColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            activeIcon: Icon(Icons.people_alt),
            label: '회원 관리',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_tennis_outlined),
            activeIcon: Icon(Icons.sports_tennis),
            label: '경기 매칭',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner_outlined),
            activeIcon: Icon(Icons.qr_code_2),
            label: '웹 접속 QR',
          ),
        ],
      ),
    );
  }
}

