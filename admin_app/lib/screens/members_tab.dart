import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/app_state.dart';
import '../models/member.dart';

class MembersTab extends StatefulWidget {
  const MembersTab({super.key});

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> {
  String _searchQuery = '';
  String _selectedTierFilter = '전체';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final members = appState.members;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 필터링 적용
    final filteredMembers = members.where((m) {
      final matchesSearch = m.name.contains(_searchQuery) || m.displayName.contains(_searchQuery);
      final matchesTier = _selectedTierFilter == '전체' || m.tier == _selectedTierFilter;
      return matchesSearch && matchesTier;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 관리'),
        elevation: 1,
        actions: [
          // 테마 전환 버튼 (시스템 -> 라이트 -> 다크 3단계 순환)
          IconButton(
            icon: Icon(
              appState.themeMode == ThemeMode.system
                  ? Icons.brightness_auto
                  : (appState.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
            ),
            tooltip: '테마: ${appState.themeModeDescription} (터치하여 순환)',
            onPressed: () {
              final msg = appState.cycleTheme();
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: '회원 추가',
            onPressed: () => _showAddMemberDialog(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'all_present') {
                appState.setAllAttendance(true);
              } else if (value == 'all_absent') {
                appState.setAllAttendance(false);
              } else if (value == 'reset_matches') {
                appState.resetMatchCounts();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all_present', child: Text('전체 참석 처리')),
              const PopupMenuItem(value: 'all_absent', child: Text('전체 불참 처리')),
              const PopupMenuItem(value: 'reset_matches', child: Text('오늘 경기 횟수 초기화')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          // 상단 요약 바 & 다중 관리자 실시간 싱크 상태 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '전체: ${members.length}명 | 참석: ${appState.presentCount}명',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (appState.isRemoteSyncActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('실시간 연동중', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                Text(
                  '불참: ${members.length - appState.presentCount}명',
                  style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),

          // 검색 및 6단계 급수(S~E) 필터
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '이름 검색...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedTierFilter,
                  items: ['전체', 'S', 'A', 'B', 'C', 'D', 'E']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTierFilter = val);
                  },
                )
              ],
            ),
          ),

          // 회원 리스트
          Expanded(
            child: ListView.separated(
              itemCount: filteredMembers.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = filteredMembers[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getTierColor(member.tier),
                    child: Text(
                      member.tier,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        member.gender == 'M' ? '남' : '여',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                  subtitle: Text('오늘 치른 경기: ${member.matchCountToday}회'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.isPresent ? '참석' : '미참석',
                        style: TextStyle(
                          color: member.isPresent ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Switch(
                        value: member.isPresent,
                        activeColor: Colors.green,
                        onChanged: (_) => appState.toggleAttendance(member.id),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier.toUpperCase()) {
      case 'S':
        return Colors.purple.shade600;
      case 'A':
        return Colors.red.shade500;
      case 'B':
        return Colors.orange.shade600;
      case 'C':
        return Colors.blue.shade600;
      case 'D':
        return Colors.teal.shade600;
      case 'E':
      case '초심':
      default:
        return Colors.green.shade600;
    }
  }

  void _showAddMemberDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    String selectedTier = 'C';
    String selectedGender = 'M';
    bool isGuest = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('신규 회원 / 게스트 등록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '이름 (게스트는 자동 G 접두사)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('급수: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedTier,
                    items: ['S', 'A', 'B', 'C', 'D', 'E']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedTier = val);
                    },
                  ),
                  const Spacer(),
                  const Text('성별: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedGender,
                    items: const [
                      DropdownMenuItem(value: 'M', child: Text('남')),
                      DropdownMenuItem(value: 'F', child: Text('여')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedGender = val);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('게스트(비회원)로 등록', style: TextStyle(fontSize: 14)),
                value: isGuest,
                onChanged: (val) {
                  setDialogState(() => isGuest = val ?? false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              onPressed: () {
                final rawName = nameCtrl.text.trim();
                if (rawName.isNotEmpty) {
                  final formattedName = isGuest && !rawName.startsWith('G ') ? 'G $rawName' : rawName;
                  final newMember = Member(
                    id: const Uuid().v4().substring(0, 8),
                    name: formattedName,
                    tier: selectedTier,
                    gender: selectedGender,
                    isPresent: true,
                    hasSubmittedShuttle: true,
                    isGuest: isGuest,
                  );
                  context.read<AppState>().addMember(newMember);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
  }
}

