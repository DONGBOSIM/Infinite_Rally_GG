import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/game_match.dart';
import '../models/member.dart';
import '../services/tts_service.dart';

class MatchTab extends StatelessWidget {
  const MatchTab({super.key});

  static final TtsService _ttsService = TtsService();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentGames = appState.currentGames;
    final upcomingGames = appState.upcomingGames;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('게임 매칭 및 코트 관리'),
            if (appState.isRemoteSyncActive) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('동기화중', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        elevation: 1,
        actions: [
          // 전체 코트 순차 음성 호명 버튼
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '전체 코트 순차 호명 📢',
            onPressed: () {
              if (currentGames.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('현재 진행 중인 경기가 없습니다.')),
                );
                return;
              }
              _ttsService.speakAllCourts(currentGames);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('전체 코트를 순서대로 호명합니다 📢')),
              );
            },
          ),
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
            icon: const Icon(Icons.campaign),
            tooltip: '공지사항 수정',
            onPressed: () => _showNoticeDialog(context, appState),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 매칭 컨트롤 패널
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '사용 코트 수:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: appState.courtCount > 1
                                  ? () => appState.setCourtCount(appState.courtCount - 1)
                                  : null,
                            ),
                            Text(
                              '${appState.courtCount}개 코트',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: appState.courtCount < 10
                                  ? () => appState.setCourtCount(appState.courtCount + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    // 4코트 레슨 모드 원클릭 토글
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('제 4코트 레슨 모드', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(
                        appState.isLessonCourtEnabled
                            ? '1~3코트 게임 진행 / 4코트 레슨 코트로 운영'
                            : '1~4코트 전체 게임 코트로 운영',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                      ),
                      value: appState.isLessonCourtEnabled,
                      activeColor: Colors.amber.shade700,
                      onChanged: (val) => appState.toggleLessonCourt(val),
                    ),
                    const Divider(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('공평 자동 매칭 생성', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              if (appState.matchEligibleCount < 4 &&
                                  !(appState.isLessonCourtEnabled && appState.activeLessonCount > 0)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('콕을 제출한 경기 참여 회원이 4명 이상이어야 합니다. (현재 콕 제출: ${appState.matchEligibleCount}명)'),
                                  ),
                                );
                                return;
                              }
                              appState.generateMatches();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('출전 횟수와 급수를 고려한 최적의 매칭이 생성되었습니다.')),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 현재 코트별 경기 현황
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '코트별 경기 현황 (${currentGames.length}개 진행)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (currentGames.isNotEmpty)
                  Text(
                    '총 출전: ${currentGames.fold<int>(0, (sum, g) => sum + (g.courtType == 'lesson' ? g.lessonStudents.length : (g.teamA.length + g.teamB.length)))}명',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (currentGames.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.sports_tennis, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('현재 매칭된 경기가 없습니다.'),
                    const SizedBox(height: 4),
                    const Text(
                      '위의 [공평 자동 매칭 생성] 버튼을 눌러주세요.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: currentGames.length,
                itemBuilder: (context, index) {
                  final game = currentGames[index];
                  if (game.courtType == 'lesson' || game.isLesson) {
                    return _buildLessonCourtCard(context, game, appState, isDark);
                  }
                  return _buildRegularGameCard(context, game, appState, isDark);
                },
              ),

            const SizedBox(height: 16),

            // 다음 대기 경기 리스트
            if (upcomingGames.isNotEmpty) ...[
              Text(
                '다음 대기 경기 (${upcomingGames.length}팀 대기 중)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: upcomingGames.length,
                itemBuilder: (context, index) {
                  final wait = upcomingGames[index];
                  return Card(
                    color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: isDark ? const Color(0xFF334155) : Colors.grey.shade400,
                        child: Text('${wait['order']}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                      title: Text(
                        '${(wait['teamA'] as List).join(', ')}  VS  ${(wait['teamB'] as List).join(', ')}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      trailing: Text(
                        '${wait['designatedCourt']}코트 예정',
                        style: TextStyle(
                          color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
      // 하단 Firestore 원클릭 실시간 업로드 버튼
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: appState.isUploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.cloud_upload),
          label: Text(
            appState.isUploading ? 'Firestore 동기화 중...' : '회원 웹페이지로 실시간 업로드 (DB 동기화)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: appState.isUploading
              ? null
              : () async {
                  final ok = await appState.uploadToFirestore();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(appState.lastUploadMessage ?? ''),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
        ),
      ),
    );
  }

  void _showNoticeDialog(BuildContext context, AppState appState) {
    final ctrl = TextEditingController(text: appState.notice);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('실시간 공지사항 수정'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '회원들에게 전달할 공지사항을 입력하세요.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              appState.setNotice(ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  // 일반 복식 경기 카드 (1~3코트 또는 레슨 모드 미사용 시)
  Widget _buildRegularGameCard(BuildContext context, GameMatch game, AppState appState, bool isDark) {
    final isFinished = game.status == 'finished';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFinished ? Colors.grey.shade300 : Colors.blue.shade300,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '제 ${game.courtNumber} 코트',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '시작: ${game.startTime}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    if (game.isFixedPair) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF581C87) : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isDark ? Colors.purple.shade700 : Colors.purple.shade300),
                        ),
                        child: Text(
                          '고정페어',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.purple.shade200 : Colors.purple.shade800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (!isFinished) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          foregroundColor: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                          side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.volume_up, size: 14),
                        label: const Text('호명 📢', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _ttsService.speakCourt(game),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (!isFinished)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('경기 종료'),
                        onPressed: () {
                          appState.finishGame(game.courtNumber);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('제 ${game.courtNumber} 코트 경기가 종료되어 경기 횟수가 반영되었습니다.')),
                          );
                        },
                      )
                    else
                      const Chip(
                        label: Text('종료됨', style: TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                // Team A
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E3A5F) : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.blue.shade700 : Colors.blue.shade200,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team A',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...game.teamA.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${p.name} (${p.tier})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ),
                // Team B
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF4C1D4F) : Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.pink.shade700 : Colors.pink.shade200,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Team B',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.pink.shade300 : Colors.pink.shade800,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...game.teamB.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${p.name} (${p.tier})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 레슨 전용 코트 카드 (제 4코트 레슨 모드 활성화 시) - 레슨자 이름 및 레슨 대기자 명단만 표시
  Widget _buildLessonCourtCard(BuildContext context, GameMatch game, AppState appState, bool isDark) {
    final isFinished = game.status == 'finished';
    final waitingMembers = appState.waitingLessonMembers;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFinished ? Colors.grey.shade400 : (isDark ? Colors.amber.shade700 : Colors.amber.shade600),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 레슨 코트 배지 & 지도 코치명
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '제 ${game.courtNumber} 코트 (레슨)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Text(
                        '지도: ${game.lessonCoach.isNotEmpty ? game.lessonCoach : "코치님"}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (!isFinished) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          foregroundColor: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                          side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.volume_up, size: 14),
                        label: const Text('호명 📢', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _ttsService.speakCourt(game),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (!isFinished)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('레슨 완료'),
                        onPressed: () {
                          appState.finishGame(game.courtNumber);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('제 ${game.courtNumber} 코트 레슨이 완료 처리되었습니다.')),
                          );
                        },
                      )
                    else
                      const Chip(
                        label: Text('레슨 완료됨', style: TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 16),

            // 현재 레슨 참여자 (Active)
            Row(
              children: [
                Icon(Icons.sports_tennis, size: 16, color: isDark ? Colors.purple.shade300 : Colors.purple.shade700),
                const SizedBox(width: 6),
                Text(
                  '현재 레슨 참여자 (${game.lessonStudents.length}명)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.purple.shade300 : Colors.purple.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (game.lessonStudents.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '현재 레슨 중인 회원이 없습니다.\n[회원 관리] 탭에서 회원의 상태를 [레슨 진행]으로 지정해주세요.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, height: 1.4),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: game.lessonStudents.map<Widget>((s) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF581C87) : Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.purple.shade600 : Colors.purple.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: _getTierColor(s.tier),
                          child: Text(s.tier, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          s.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // 다음 레슨 대기 명단 (Waiting)
            Row(
              children: [
                Icon(Icons.hourglass_top, size: 14, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800),
                const SizedBox(width: 6),
                Text(
                  '다음 레슨 대기 명단 (${waitingMembers.length}명)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (waitingMembers.isEmpty)
              Text('대기 중인 레슨 신청자가 없습니다.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List.generate(waitingMembers.length, (idx) {
                  final wm = waitingMembers[idx];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF78350F) : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isDark ? Colors.amber.shade700 : Colors.amber.shade300),
                    ),
                    child: Text(
                      '대기 ${idx + 1}번: ${wm.name} (${wm.tier})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                      ),
                    ),
                  );
                }),
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

