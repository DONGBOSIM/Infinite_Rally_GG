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

    // 필터링 적용
    final filteredMembers = members.where((m) {
      final matchesSearch = m.name.contains(_searchQuery);
      final matchesTier = _selectedTierFilter == '전체' || m.tier == _selectedTierFilter;
      return matchesSearch && matchesTier;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 명단 관리 (50여 명)'),
        elevation: 1,
        actions: [
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
          // 상단 요약 바
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '전체: ${members.length}명 | 참석: ${appState.presentCount}명',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '불참: ${members.length - appState.presentCount}명',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),

          // 검색 및 급수 필터
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
                  items: ['전체', 'A', 'B', 'C', 'D', '초심']
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
    switch (tier) {
      case 'A':
        return Colors.red.shade400;
      case 'B':
        return Colors.orange.shade400;
      case 'C':
        return Colors.blue.shade400;
      case 'D':
        return Colors.teal.shade400;
      default:
        return Colors.purple.shade300;
    }
  }

  void _showAddMemberDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    String selectedTier = 'C';
    String selectedGender = 'M';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('신규 회원 등록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '회원 이름'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('급수: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedTier,
                    items: ['A', 'B', 'C', 'D', '초심']
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
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final newMember = Member(
                    id: const Uuid().v4().substring(0, 8),
                    name: nameCtrl.text.trim(),
                    tier: selectedTier,
                    gender: selectedGender,
                    isPresent: true,
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

