import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../models/member.dart';
import '../services/ocr_service.dart';

class MembersTab extends StatefulWidget {
  const MembersTab({super.key});

  @override
  State<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<MembersTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OcrService _ocrService = OcrService();

  String _searchQuery = '';
  String _selectedTierFilter = '전체';
  bool _isOcrProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final regularMembers = appState.regularMembers;
    final todayAttendees = appState.todayAttendees;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 및 출석 관리'),
        elevation: 1,
        actions: [
          // 원클릭 클라우드 DB 동기화 버튼 (회원 명부 & 당일 출석)
          if (appState.isUploading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: '클라우드 DB 동기화 (회원 명부 & 출석)',
              onPressed: () async {
                final ok = await appState.syncAllToCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(appState.lastUploadMessage ?? ''),
                      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  );
                }
              },
            ),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'all_present') {
                appState.setAllAttendance(true);
              } else if (value == 'all_absent') {
                appState.setAllAttendance(false);
              } else if (value == 'reset_matches') {
                appState.resetMatchCounts();
              } else if (value == 'reload_members') {
                await appState.loadMasterMembers();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('클라우드에서 최신 회원 명부를 불러왔습니다.')),
                  );
                }
              } else if (value == 'bulk_import') {
                _showBulkImportDialog(context, appState);
              } else if (value == 'clear_all') {
                _showClearAllMembersDialog(context, appState);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'bulk_import',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 18, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('시트(엑셀) 회원 일괄 등록'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'all_present', child: Text('전체 참석 처리')),
              const PopupMenuItem(value: 'all_absent', child: Text('전체 불참 처리')),
              const PopupMenuItem(value: 'reset_matches', child: Text('오늘 경기 횟수 초기화')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'reload_members', child: Text('클라우드 회원 명부 새로고침')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('전체 회원 목록 비우기', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? Colors.blue.shade400 : Colors.indigo.shade700,
          labelColor: isDark ? Colors.blue.shade300 : Colors.indigo.shade800,
          unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          tabs: [
            Tab(
              icon: const Icon(Icons.how_to_reg, size: 20),
              text: '오늘 참여자 (${todayAttendees.length}명)',
            ),
            Tab(
              icon: const Icon(Icons.groups, size: 20),
              text: '전체 회원 (${regularMembers.length}명)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 탭 1: 오늘 참여자 (스마트 출석 & 콕 제출 & OCR)
          _buildTodayAttendeesTab(context, appState, isDark),

          // 탭 2: 전체 회원 관리 (DB 명부 및 검색)
          _buildAllMembersTab(context, appState, isDark),
        ],
      ),
    );
  }

  // ==========================================
  // 탭 1: 오늘 참여자 화면 (콕 제출, 레슨 토글, OCR)
  // ==========================================
  Widget _buildTodayAttendeesTab(BuildContext context, AppState appState, bool isDark) {
    final attendees = appState.todayAttendees;

    return Column(
      children: [
        // 상단 스마트 액션 패널 (투표 사진 OCR & 게스트 간편 추가)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: isDark ? const Color(0xFF1E293B) : Colors.indigo.shade50,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        appState.todayGuestCount > 0
                            ? '참석: ${attendees.length}명 (G ${appState.todayGuestCount})'
                            : '참석: ${attendees.length}명',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '콕 제출: ${appState.submittedShuttleCount}명',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '레슨: 대기 ${appState.waitingLessonCount} / 진행 ${appState.activeLessonCount}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (appState.isRemoteSyncActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('실시간 연동중', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // 투표 캡처 사진 OCR 버튼
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isOcrProcessing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.document_scanner, size: 18),
                      label: Text(_isOcrProcessing ? '사진 분석 중...' : '투표 사진 OCR', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: _isOcrProcessing ? null : () => _showOcrSourceDialog(context, appState),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 게스트 간편 수동 추가 버튼
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.blue.shade300 : Colors.indigo.shade800,
                        side: BorderSide(color: isDark ? Colors.blue.shade600 : Colors.indigo.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('+ 게스트 추가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => _showAddGuestDialog(context, appState),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 오늘 참여자 리스트
        Expanded(
          child: attendees.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.how_to_reg_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('오늘 참석으로 등록된 회원이 없습니다.', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(
                        '위의 [투표 사진 OCR]을 누르거나\n[전체 회원] 탭에서 참석자를 체크해 주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: attendees.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = attendees[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: _getTierColor(member.tier),
                        radius: 18,
                        child: Text(
                          member.tier,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      title: Row(
                        children: [
                          Text(
                            member.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: member.isGuest ? Colors.amber.shade700 : null,
                            ),
                          ),
                          if (member.isGuest) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('게스트', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Text(
                            member.gender == 'M' ? '남' : '여',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('오늘 출전: ${member.matchCountToday}게임', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(height: 3),
                          Builder(builder: (context) {
                            final fixedPartner = appState.getFixedPartner(member.id);
                            if (fixedPartner != null) {
                              return InkWell(
                                onTap: () => _showFixedPartnerDialog(context, appState, member),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: isDark ? Colors.blue.shade700 : Colors.blue.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.link, size: 12, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                      const SizedBox(width: 3),
                                      Text(
                                        '고정페어: ${fixedPartner.name}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.blue.shade200 : Colors.blue.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              return InkWell(
                                onTap: () => _showFixedPartnerDialog(context, appState, member),
                                child: Text(
                                  '+ 고정 파트너 지정',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.blue.shade300 : Colors.indigo.shade600,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              );
                            }
                          }),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 콕 제출 토글 버튼 (누른 회원만 출석자로 게임 매칭 포함)
                          Tooltip(
                            message: member.hasSubmittedShuttle ? '콕 제출 완료 (게임 매칭 포함)' : '콕 미제출 (게임 매칭 제외)',
                            child: InkWell(
                              onTap: () => appState.toggleShuttleSubmission(member.id),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: member.hasSubmittedShuttle
                                      ? (isDark ? Colors.green.shade900.withOpacity(0.4) : Colors.green.shade50)
                                      : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                                  border: Border.all(
                                    color: member.hasSubmittedShuttle ? Colors.green.shade600 : Colors.grey.shade400,
                                    width: member.hasSubmittedShuttle ? 1.5 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      member.hasSubmittedShuttle ? Icons.check_circle : Icons.radio_button_unchecked,
                                      size: 14,
                                      color: member.hasSubmittedShuttle ? Colors.green.shade600 : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      member.hasSubmittedShuttle ? '콕 제출됨' : '콕 미제출',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: member.hasSubmittedShuttle ? Colors.green.shade600 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // 레슨 상태 순환 버튼 (터치: 없음 -> 레슨 대기 -> 레슨 진행 -> 없음)
                          Tooltip(
                            message: '레슨 순환 (터치: 대기 -> 진행 -> 해제)',
                            child: InkWell(
                              onTap: () => appState.cycleLessonStatus(member.id),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: member.lessonStatus == 'active'
                                      ? (isDark ? const Color(0xFF581C87) : Colors.purple.shade100)
                                      : (member.lessonStatus == 'waiting'
                                          ? (isDark ? const Color(0xFF78350F) : Colors.amber.shade100)
                                          : (isDark ? Colors.grey.shade800 : Colors.grey.shade100)),
                                  border: Border.all(
                                    color: member.lessonStatus == 'active'
                                        ? Colors.purple.shade600
                                        : (member.lessonStatus == 'waiting'
                                            ? Colors.amber.shade700
                                            : Colors.grey.shade400),
                                    width: member.lessonStatus != 'none' ? 1.5 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (member.lessonStatus == 'active') ...[
                                      Icon(Icons.sports_tennis, size: 13, color: isDark ? Colors.purple.shade200 : Colors.purple.shade800),
                                      const SizedBox(width: 3),
                                      Text(
                                        '레슨 진행',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.purple.shade200 : Colors.purple.shade800,
                                        ),
                                      ),
                                    ] else if (member.lessonStatus == 'waiting') ...[
                                      Icon(Icons.hourglass_top, size: 13, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                                      const SizedBox(width: 3),
                                      Text(
                                        '레슨 대기',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                                        ),
                                      ),
                                    ] else ...[
                                      Text(
                                        '레슨',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),

                          // 정회원은 참석 해제(불참 전환), 게스트는 즉시 삭제
                          IconButton(
                            icon: Icon(
                              member.isGuest ? Icons.delete_outline : Icons.close,
                              size: 18,
                              color: member.isGuest ? Colors.redAccent : Colors.grey,
                            ),
                            tooltip: member.isGuest ? '게스트 삭제' : '참석 해제',
                            onPressed: () {
                              if (member.isGuest) {
                                appState.removeMember(member.id);
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${member.name} 게스트가 삭제되었습니다.'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              } else {
                                appState.toggleAttendance(member.id);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // 탭 2: 전체 회원 관리 화면 (검색, 급수필터, 회원추가)
  // ==========================================
  Widget _buildAllMembersTab(BuildContext context, AppState appState, bool isDark) {
    // ⭐️ 게스트는 전체 회원 명단에서 100% 제외하고 순수 정식 회원만 표시
    final members = appState.regularMembers;

    final filteredMembers = members.where((m) {
      final matchesSearch = m.name.contains(_searchQuery) || m.displayName.contains(_searchQuery);
      final matchesTier = _selectedTierFilter == '전체' || m.tier == _selectedTierFilter;
      return matchesSearch && matchesTier;
    }).toList();

    return Column(
      children: [
        // 상단 검색 & 필터 & 신규 회원 추가 바
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '회원 이름 검색...',
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
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.table_chart, color: Colors.indigo),
                tooltip: '시트(엑셀) 일괄 등록',
                onPressed: () => _showBulkImportDialog(context, appState),
              ),
              IconButton(
                icon: const Icon(Icons.person_add),
                tooltip: '신규 회원 추가',
                onPressed: () => _showAddMemberDialog(context),
              ),
            ],
          ),
        ),

        // 전체 회원 리스트
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
                      member.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      member.gender == 'M' ? '남' : '여',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
                subtitle: Text('급수: ${member.tier}조 | 성별: ${member.gender == 'M' ? "남성" : "여성"}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    member.isPresent
                        ? Tooltip(
                            message: '오늘 참여자로 등록되어 있습니다 (터치 시 목록에서 제외)',
                            child: InkWell(
                              onTap: () => appState.toggleAttendance(member.id),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark ? Colors.blue.shade700 : Colors.blue.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 14, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      '오늘 참여중',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: isDark ? Colors.blue.shade300 : Colors.indigo.shade800,
                              side: BorderSide(color: isDark ? Colors.blue.shade700 : Colors.indigo.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.person_add_alt, size: 14),
                            label: const Text('+ 오늘 참여', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () => appState.toggleAttendance(member.id),
                          ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade300),
                      tooltip: '회원 삭제',
                      onPressed: () => _confirmDeleteMember(context, appState, member),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // OCR 투표 캡처 사진 선택 및 분석 다이얼로그
  // ==========================================
  void _showOcrSourceDialog(BuildContext context, AppState appState) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('투표 캡처 사진 선택 (Google ML Kit 온디바이스)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.indigo),
              title: const Text('사진 앨범(갤러리)에서 선택'),
              subtitle: const Text('카카오톡 또는 밴드 투표 캡처 이미지'),
              onTap: () {
                Navigator.pop(ctx);
                _runOcrProcess(appState, fromCamera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.indigo),
              title: const Text('카메라로 직접 촬영'),
              onTap: () {
                Navigator.pop(ctx);
                _runOcrProcess(appState, fromCamera: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runOcrProcess(AppState appState, {required bool fromCamera}) async {
    setState(() => _isOcrProcessing = true);

    try {
      final xFile = fromCamera
          ? await _ocrService.pickImageFromCamera()
          : await _ocrService.pickImageFromGallery();

      if (xFile == null) {
        setState(() => _isOcrProcessing = false);
        return;
      }

      final result = await _ocrService.processVoteImage(
        imagePath: xFile.path,
        allMembers: appState.members,
      );

      if (!mounted) return;
      setState(() => _isOcrProcessing = false);

      _showOcrResultDialog(context, appState, result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOcrProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR 처리 중 오류: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showOcrResultDialog(BuildContext context, AppState appState, OcrResult result) {
    // ⭐️ 매칭 성공 회원 및 미등록 후보를 다이얼로그 내부 상태로 복사
    final currentMatchedMembers = List<Member>.from(result.matchedMembers);
    final currentUnmatched = List<ParsedAttendeeCandidate>.from(result.unmatchedCandidates);
    final selectedMemberIds = Set<String>.from(currentMatchedMembers.map((m) => m.id));
    final matchedOriginalNames = Map<String, String>.from(result.matchedOriginalNames);
    final newlyAddedMemberIds = <String>{};
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.document_scanner, color: Colors.indigo),
              SizedBox(width: 8),
              Text('투표 사진 분석 결과', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '매칭된 회원 ${currentMatchedMembers.length}명 / 미등록 회원 ${currentUnmatched.length}명',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '※ 미등록 인원은 [회원 등록]을 누르면 즉시 상단 참석 목록으로 이동합니다.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                  const Divider(height: 16),

                  // 1. 상단: 기존/신규 회원 참석 매칭 목록
                  if (currentMatchedMembers.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('✅ 참석 회원 매칭 (${selectedMemberIds.length}/${currentMatchedMembers.length}):',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Row(
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(40, 24),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedMemberIds.addAll(currentMatchedMembers.map((m) => m.id));
                                });
                              },
                              child: const Text('전체', style: TextStyle(fontSize: 11)),
                            ),
                            const Text('/', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(40, 24),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedMemberIds.clear();
                                });
                              },
                              child: const Text('해제', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...currentMatchedMembers.map((m) {
                      final orig = matchedOriginalNames[m.id];
                      final isOmitted = orig != null && orig != m.name;
                      final isNew = newlyAddedMemberIds.contains(m.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Text('${m.name} (${m.tier}조)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            if (isNew) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.green.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('신규 등록', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                              ),
                            ] else if (isOmitted) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('사진: $orig', style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
                              ),
                            ],
                          ],
                        ),
                        value: selectedMemberIds.contains(m.id),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedMemberIds.add(m.id);
                            } else {
                              selectedMemberIds.remove(m.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                  ],

                  // 2. 하단: 미등록 회원 목록 (회원 등록 시 위쪽으로 이동!)
                  if (currentUnmatched.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.person_add_alt_1, size: 16, color: Colors.orange),
                        const SizedBox(width: 6),
                        Text('미등록 회원 (${currentUnmatched.length}명)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('※ 회원 명단에 없는 인원입니다. [회원 등록]을 누르면 즉시 상단 참석 목록으로 이동합니다.',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    ...currentUnmatched.map((cand) {
                      final genderStr = cand.gender == 'F' ? '여' : '남';
                      final genderColor = cand.gender == 'F' ? Colors.pink : Colors.blue;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800.withAlpha(120) : Colors.orange.shade50.withAlpha(100),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withAlpha(80)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(cand.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: genderColor.withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(genderStr, style: TextStyle(fontSize: 10, color: genderColor, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  if (cand.region.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text('지역: ${cand.region}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  ],
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              icon: const Icon(Icons.person_add, size: 14),
                              label: const Text('회원 등록'),
                              onPressed: () {
                                _showQuickRegisterMemberFromOcrDialog(
                                  context: context,
                                  candidate: cand,
                                  onRegistered: (newMember) {
                                    appState.addMember(newMember);
                                    setDialogState(() {
                                      currentUnmatched.remove(cand);
                                      currentMatchedMembers.add(newMember);
                                      selectedMemberIds.add(newMember.id);
                                      newlyAddedMemberIds.add(newMember.id);
                                      matchedOriginalNames[newMember.id] = cand.name;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('${newMember.name} 님이 회원으로 등록되어 상단 참석 목록에 추가되었습니다!'),
                                        backgroundColor: Colors.green,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  if (currentMatchedMembers.isEmpty && currentUnmatched.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text('사진에서 이름을 인식하지 못했습니다.\n선명한 캡처 사진으로 다시 시도해 주세요.', textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                appState.applyOcrBatch(
                  memberIds: selectedMemberIds.toList(),
                  newGuestNames: const [], // ⭐️ 투표 사진에서 게스트 자동 추가 완전 제거
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${selectedMemberIds.length}명의 회원이 오늘 참석자로 등록되었습니다!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: Text('선택 회원 일괄 참석 처리 (${selectedMemberIds.length}명)'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // OCR 미등록 회원 간편 회원 등록 다이얼로그
  // ==========================================
  void _showQuickRegisterMemberFromOcrDialog({
    required BuildContext context,
    required ParsedAttendeeCandidate candidate,
    required ValueChanged<Member> onRegistered,
  }) {
    final nameCtrl = TextEditingController(text: candidate.name);
    String selectedGender = candidate.gender;
    String selectedTier = 'C';
    final tiers = ['S', 'A', 'B', 'C', 'D', 'E'];

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add_alt_1, color: Colors.indigo),
              SizedBox(width: 8),
              Text('신규 회원 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이름 (성 포함 풀네임 확인):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '이름 입력 (예: 심재호)',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('성별:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('남성 (M)')),
                      selected: selectedGender == 'M',
                      selectedColor: Colors.blue.withAlpha(50),
                      onSelected: (val) {
                        if (val) setDlgState(() => selectedGender = 'M');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('여성 (F)')),
                      selected: selectedGender == 'F',
                      selectedColor: Colors.pink.withAlpha(50),
                      onSelected: (val) {
                        if (val) setDlgState(() => selectedGender = 'F');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('급수:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: tiers.map((tier) {
                  final isSel = selectedTier == tier;
                  return ChoiceChip(
                    label: Text(tier),
                    selected: isSel,
                    selectedColor: Colors.indigo.withAlpha(50),
                    onSelected: (val) {
                      if (val) setDlgState(() => selectedTier = tier);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final trimmedName = nameCtrl.text.trim();
                if (trimmedName.isEmpty) return;

                final newMember = Member(
                  id: "user_${DateTime.now().millisecondsSinceEpoch}_${trimmedName.hashCode}",
                  name: trimmedName,
                  tier: selectedTier,
                  gender: selectedGender,
                  isPresent: true,
                  hasSubmittedShuttle: false,
                  matchCountToday: 0,
                );

                Navigator.pop(dlgCtx);
                onRegistered(newMember);
              },
              child: const Text('등록 및 매칭 이동'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 게스트 간편 추가 다이얼로그
  // ==========================================
  void _showAddGuestDialog(BuildContext context, AppState appState) {
    final nameCtrl = TextEditingController();
    String selectedTier = 'C';
    String selectedGender = 'M';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('게스트(비회원) 간편 등록'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '게스트 이름',
                  hintText: '이름 입력 (G 접두사는 자동 부여됨)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('추정 급수: '),
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  appState.addGuest(
                    name: name,
                    tier: selectedTier,
                    gender: selectedGender,
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('게스트 "$name"님이 오늘 참여자로 등록되었습니다.')),
                  );
                }
              },
              child: const Text('등록'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 신규 정회원 등록 다이얼로그
  // ==========================================
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            ElevatedButton(
              onPressed: () {
                final rawName = nameCtrl.text.trim();
                if (rawName.isNotEmpty) {
                  final newMember = Member(
                    id: const Uuid().v4().substring(0, 8),
                    name: rawName,
                    tier: selectedTier,
                    gender: selectedGender,
                    isPresent: true,
                    hasSubmittedShuttle: true,
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

  // 고정 페어(파트너) 지정 및 해제 다이얼로그
  void _showFixedPartnerDialog(BuildContext context, AppState appState, Member member) {
    final currentPartner = appState.getFixedPartner(member.id);
    final candidates = appState.todayAttendees.where((m) => m.id != member.id).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.link, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${member.name}님의 고정 페어',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentPartner != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: _getTierColor(currentPartner.tier),
                            child: Text(currentPartner.tier, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '현재 페어: ${currentPartner.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13),
                          ),
                        ],
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          appState.clearFixedPartner(member.id);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${member.name}님의 고정 페어가 해제되었습니다.')),
                          );
                        },
                        child: const Text('해제'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('파트너 변경:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ] else ...[
                const Text(
                  '고정 파트너로 묶을 선수를 선택하세요.\n(게임 매칭 시 항상 같은 팀으로 자동 편성됩니다)',
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                ),
              ],
              const SizedBox(height: 8),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('선택 가능한 다른 참여자가 없습니다.')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final candidate = candidates[index];
                      final isCurrent = currentPartner?.id == candidate.id;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: _getTierColor(candidate.tier),
                          child: Text(candidate.tier, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(candidate.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: candidate.fixedPartnerId != null && !isCurrent
                            ? Text('다른 회원과 페어 중', style: TextStyle(fontSize: 10, color: Colors.orange.shade700))
                            : null,
                        trailing: isCurrent
                            ? const Chip(label: Text('현재 페어', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact)
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                onPressed: () {
                                  appState.setFixedPartner(member.id, candidate.id);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${member.name}님과 ${candidate.name}님이 고정 페어로 지정되었습니다!')),
                                  );
                                },
                                child: const Text('선택'),
                              ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
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

  // 개별 회원 삭제 확인 다이얼로그
  void _confirmDeleteMember(BuildContext context, AppState appState, Member member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 삭제'),
        content: Text('정말 \'${member.displayName}\' 회원을 명부에서 완전히 삭제하시겠습니까?\n삭제 후 클라우드에 자동 반영됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              appState.removeMember(member.id);
              await appState.syncAllToCloud();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('\'${member.displayName}\' 회원이 삭제되었습니다.')),
                );
              }
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  // 전체 회원 목록 비우기 (관리자 패스워드 검증)
  void _showClearAllMembersDialog(BuildContext context, AppState appState) {
    final pwdController = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('전체 회원 목록 비우기'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚠️ 주의: 현재 등록된 모든 회원과 당일 세션 데이터가 완전히 삭제됩니다.\n\n실수로 인한 초기화를 방지하기 위해 관리자 확인 암호를 입력해주세요.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pwdController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '관리자 암호 입력 (기본: 1234)',
                  errorText: errorMessage,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final input = pwdController.text.trim();
                // 패스워드 검증 (1234 또는 infinite)
                if (input != '1234' && input != 'infinite') {
                  setDialogState(() {
                    errorMessage = '암호가 일치하지 않습니다. (기본 암호: 1234)';
                  });
                  return;
                }

                Navigator.pop(ctx);
                appState.clearAllMembers();
                final ok = await appState.syncAllToCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? '회원 목록이 모두 초기화되었으며 클라우드에 반영되었습니다.'
                          : '초기화는 되었으나 클라우드 동기화 결과를 확인해주세요.'),
                      backgroundColor: ok ? Colors.green.shade700 : Colors.red,
                    ),
                  );
                }
              },
              child: const Text('모두 비우기'),
            ),
          ],
        ),
      ),
    );
  }

  // 시트(엑셀/구글 스프레드시트) 회원 일괄 등록 다이얼로그
  void _showBulkImportDialog(BuildContext context, AppState appState) {
    final textController = TextEditingController();
    bool replaceAll = true; // 디폴트는 기존 예제 회원 목록을 완전히 교체하는 것!

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.table_chart, color: Colors.indigo),
              SizedBox(width: 8),
              Text('시트(엑셀) 회원 일괄 등록'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '구글 스프레드시트나 엑셀에서 회원 표를 복사(Ctrl+C)하여 아래에 붙여넣으세요.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    '📌 형식: 이름 [탭/쉼표/공백] 급수(S~E) [탭/쉼표/공백] 성별(남/여)\n'
                    '예시:\n'
                    '홍길동\tA\t남\n'
                    '김철수\tB\t남\n'
                    '이영희\tC\t여',
                    style: TextStyle(fontSize: 11, color: Colors.black87, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: '여기에 복사한 텍스트를 붙여넣으세요...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: replaceAll,
                      onChanged: (val) {
                        setDialogState(() => replaceAll = val ?? false);
                      },
                    ),
                    const Expanded(
                      child: Text(
                        '기존 명부(예제)를 모두 지우고 이 명단으로 전체 교체 (권장)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.indigo.shade700,
                        side: BorderSide(color: Colors.indigo.shade300),
                      ),
                      icon: const Icon(Icons.attach_file, size: 16),
                      label: const Text('파일 첨부 (.csv)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        try {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['csv', 'txt'],
                            withData: true,
                          );

                          if (result != null && result.files.isNotEmpty) {
                            final file = result.files.first;
                            List<int>? bytes = file.bytes;
                            if (bytes == null && file.path != null) {
                              bytes = await File(file.path!).readAsBytes();
                            }

                            if (bytes != null && bytes.isNotEmpty) {
                              // UTF-8 BOM (0xEF, 0xBB, 0xBF) 제거
                              if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
                                bytes = bytes.sublist(3);
                              }

                              String decoded;
                              try {
                                decoded = utf8.decode(bytes);
                              } catch (_) {
                                decoded = String.fromCharCodes(bytes);
                              }

                              setDialogState(() {
                                textController.text = decoded.trim();
                              });

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('\'${file.name}\' 파일을 성공적으로 불러왔습니다!')),
                                );
                              }
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('파일 불러오기 실패: $e')),
                            );
                          }
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.paste, size: 16),
                      label: const Text('예시 채우기', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        setDialogState(() {
                          textController.text =
                              '홍길동\tA\t남\n김철수\tB\t남\n이영희\tC\t여\n박지민\tD\t여\n최민턴\tS\t남';
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final raw = textController.text.trim();
                if (raw.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('붙여넣은 텍스트가 없습니다.')),
                  );
                  return;
                }

                final count = appState.importMembersFromText(raw, replaceAll: replaceAll);
                if (count == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('인식된 회원이 없습니다. 형식을 확인해주세요.')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                final ok = await appState.syncAllToCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$count명의 회원이 일괄 등록되었으며 클라우드에 동기화되었습니다!'),
                      backgroundColor: ok ? Colors.green.shade700 : Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('일괄 등록 및 동기화'),
            ),
          ],
        ),
      ),
    );
  }
}
