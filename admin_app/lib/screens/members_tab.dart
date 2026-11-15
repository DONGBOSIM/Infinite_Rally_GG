import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
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
    final members = appState.members;
    final todayAttendees = appState.todayAttendees;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 및 출석 관리'),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
              text: '전체 회원 (${members.length}명)',
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
                        '참석: ${attendees.length}명',
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
                      subtitle: Text('오늘 출전: ${member.matchCountToday}게임', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

                          // 당일 참석 해제(불참 전환) 아이콘
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                            tooltip: '참석 해제',
                            onPressed: () => appState.toggleAttendance(member.id),
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
    final members = appState.members;

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
                trailing: member.isPresent
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
    final selectedMemberIds = Set<String>.from(result.matchedMembers.map((m) => m.id));
    final selectedGuestNames = Set<String>.from(result.potentialGuestNames);
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
                    '인식된 회원 ${result.matchedMembers.length}명 / 게스트 후보 ${result.potentialGuestNames.length}명',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '※ 등록된 인원은 [오늘 참여자]로 등록되며, 체육관에서 [콕 제출] 시 게임 매칭에 포함됩니다.',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                  const Divider(height: 16),

                  if (result.matchedMembers.isNotEmpty) ...[
                    const Text('✅ 기존 회원 참석 매칭:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...result.matchedMembers.map((m) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${m.name} (${m.tier}조)'),
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
                        )),
                    const SizedBox(height: 12),
                  ],

                  if (result.potentialGuestNames.isNotEmpty) ...[
                    const Text('➕ 게스트(미등록 인원) 후보:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber)),
                    const SizedBox(height: 4),
                    Text('체크된 인원은 "G 이름" 게스트로 자동 등록됩니다.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    ...result.potentialGuestNames.map((gName) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('G $gName'),
                          value: selectedGuestNames.contains(gName),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedGuestNames.add(gName);
                              } else {
                                selectedGuestNames.remove(gName);
                              }
                            });
                          },
                        )),
                  ],

                  if (result.matchedMembers.isEmpty && result.potentialGuestNames.isEmpty) ...[
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
                  newGuestNames: selectedGuestNames.toList(),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${selectedMemberIds.length + selectedGuestNames.length}명이 오늘 참여자로 등록되었습니다!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('선택 인원 일괄 등록'),
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
}
