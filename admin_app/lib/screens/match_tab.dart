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
              final activeGames = currentGames.where((g) => g.status == 'in_progress').toList();
              if (activeGames.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('현재 게임 진행 중인 코트가 없습니다.')),
                );
                return;
              }
              _ttsService.speakAllCourts(activeGames);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('진행 중인 코트를 순서대로 호명합니다 📢')),
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
                            label: Text(
                              '공평 자동 매칭 대기열 추가 (대기 가능: ${appState.availableMembersForQueue.length}명)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              final count = appState.addAutoMatchesToQueue();
                              if (count == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('대기 가능한 회원이 4명 이상이어야 합니다. (현재 가용 인원: ${appState.availableMembersForQueue.length}명)'),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$count개의 공평 매칭이 대기열에 추가되었습니다!'),
                                    backgroundColor: Colors.green.shade700,
                                  ),
                                );
                              }
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

            // 현재 코트별 경기 현황 (상태: 게임중... / 게임 종료 / 입장 순으로 제어)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '코트별 현황 (${currentGames.length}개 코트)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '대기열: ${upcomingGames.length}팀 대기',
                  style: TextStyle(
                    color: upcomingGames.isNotEmpty ? Colors.orange.shade800 : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

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

            const SizedBox(height: 24),

            // ==========================================
            // 다음 대기 경기 리스트 (Queue)
            // ==========================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '다음 대기 경기 (${upcomingGames.length}팀 대기 중)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (upcomingGames.isNotEmpty)
                  Text(
                    '순서대로 코트 입장 ⏳',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (upcomingGames.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Icon(Icons.hourglass_empty, size: 36, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    const Text('현재 대기 중인 매칭팀이 없습니다.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '상단의 [공평 자동 매칭] 또는 아래의 [+ 수동 대기 매칭 추가]를 눌러주세요.',
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: upcomingGames.length,
                itemBuilder: (context, index) {
                  final wait = upcomingGames[index];
                  final isFirst = index == 0; // 대기 1번 팀
                  final orderNum = wait['order'] ?? (index + 1);

                  return Card(
                    color: isFirst
                        ? (isDark ? const Color(0xFF2E1065) : Colors.amber.shade50)
                        : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isFirst
                            ? (isDark ? Colors.purple.shade400 : Colors.amber.shade600)
                            : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                        width: isFirst ? 1.5 : 1,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 상단: 순번 아바타 + 배지 + 우측 순서조정/삭제 버튼
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isFirst
                                        ? Colors.amber.shade700
                                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade400),
                                    child: Text(
                                      '$orderNum',
                                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isFirst) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade700,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('다음 입장 순번 🚀', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    '대기 $orderNum번',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isFirst ? Colors.amber.shade900 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              // 순서 위/아래 이동 및 삭제 버튼
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward, size: 16),
                                    tooltip: '순서 위로 이동',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    onPressed: index > 0 ? () => appState.moveQueueItem(index, index - 1) : null,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward, size: 16),
                                    tooltip: '순서 아래로 이동',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    onPressed: index < upcomingGames.length - 1 ? () => appState.moveQueueItem(index, index + 1) : null,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 17, color: Colors.redAccent),
                                    tooltip: '대기열에서 취소',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                    onPressed: () {
                                      appState.removeQueueItem(index);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('대기 경기 매칭이 취소되었습니다.'), duration: Duration(seconds: 1)),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // 코트처럼 좌(Team A) / 우(Team B) 분할 표시
                          Row(
                            children: [
                              // Team A 박스
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0C2844) : Colors.blue.shade50,
                                    border: Border.all(color: isDark ? Colors.blue.shade800 : Colors.blue.shade200),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Team A 🩵',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (wait['teamA'] as List).join('\n'),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.blue.shade100 : Colors.blue.shade900,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('VS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey)),
                              ),
                              // Team B 박스
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF3B162A) : Colors.red.shade50,
                                    border: Border.all(color: isDark ? Colors.red.shade800 : Colors.red.shade200),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Team B 🩷',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.pink.shade300 : Colors.red.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (wait['teamB'] as List).join('\n'),
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.pink.shade100 : Colors.red.shade900,
                                          height: 1.3,
                                        ),
                                      ),
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
                },
              ),

            const SizedBox(height: 8),

            // ⭐️ 대기열 가장 아래: [+ 수동 대기 매칭 추가] 버튼 (사용자 요청)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: const BorderSide(color: Colors.indigo, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text(
                '+ 수동 대기 매칭 추가',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () => _showManualMatchDialog(context, appState),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      // 하단 Firestore 원클릭 실시간 업로드 버튼
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              appState.isUploading ? 'Firestore 동기화 중...' : '웹 전광판 실시간 업로드 (DB 동기화)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              maxLines: 1,
            ),
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

  // ==========================================
  // 일반 복식 경기 카드 (게임중... / 게임 종료 / 입장 순으로 제어)
  // ==========================================
  Widget _buildRegularGameCard(BuildContext context, GameMatch game, AppState appState, bool isDark) {
    final isFinished = game.status == 'finished';
    final isInProgress = game.status == 'in_progress';
    final isIdle = game.status == 'idle' || (game.teamA.isEmpty && game.teamB.isEmpty);
    final hasWaitingMatch = appState.waitingQueue.isNotEmpty;

    Color statusBadgeColor;
    String statusBadgeText;
    if (isInProgress) {
      statusBadgeColor = Colors.green.shade600;
      statusBadgeText = '게임중... 🟢';
    } else if (isFinished) {
      statusBadgeColor = Colors.redAccent.shade700;
      statusBadgeText = '게임 종료 🔴';
    } else {
      statusBadgeColor = Colors.grey.shade600;
      statusBadgeText = '입장 대기 ⏳';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isInProgress
              ? (isDark ? Colors.blue.shade400 : Colors.blue.shade600)
              : (isFinished ? Colors.redAccent.shade200 : Colors.grey.shade400),
          width: isInProgress ? 1.8 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카드 상단 헤더: 1행(코트 정보 & 비우기) / 2행(진행 액션 버튼)
            // 1행: 코트 번호 & 상태 뱃지 & 시작 시간 <---> 코트 비우기
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
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBadgeColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusBadgeText,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isInProgress && game.startTime.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '시작: ${game.startTime}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ],
                ),

                // 1행 우측: 코트 비우기 버튼 (선수가 배정되어 있는 경우)
                if (!isIdle)
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('제 ${game.courtNumber} 코트 비우기'),
                          content: Text('제 ${game.courtNumber} 코트의 게임을 취소하고 빈 코트로 리셋할까요?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () {
                                Navigator.pop(ctx);
                                appState.clearCourt(game.courtNumber);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('제 ${game.courtNumber} 코트가 비워졌습니다.')),
                                );
                              },
                              child: const Text('비우기', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: isDark ? Colors.red.shade700 : Colors.red.shade300),
                        borderRadius: BorderRadius.circular(6),
                        color: isDark ? Colors.red.shade900.withOpacity(0.2) : Colors.red.shade50,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 13, color: isDark ? Colors.red.shade300 : Colors.red.shade700),
                          const SizedBox(width: 3),
                          Text(
                            '비우기 🗑️',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // 2행: 상태에 따른 메인 진행 액션 버튼 (호명 📢, 게임 종료 / 입장 🚀)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 1) 게임중... 상태일 때: [호명 📢] 및 [게임 종료] 버튼
                if (isInProgress) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      foregroundColor: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                      side: BorderSide(color: isDark ? Colors.amber.shade700 : Colors.amber.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.volume_up, size: 14),
                    label: const Text('호명 📢', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _ttsService.speakCourt(game),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.stop_circle_outlined, size: 15),
                    label: const Text('게임 종료', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      appState.finishGame(game.courtNumber);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('제 ${game.courtNumber} 코트 게임이 종료되었습니다. [입장]을 눌러 다음 팀을 진행하세요.'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],

                // 2) 게임 종료 또는 빈 코트 상태일 때: [입장 🚀] 버튼
                if (isFinished || isIdle) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasWaitingMatch ? Colors.indigo : Colors.grey.shade500,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.login, size: 15),
                    label: const Text('입장 🚀', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (!hasWaitingMatch) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('대기열에 대기 중인 팀이 없습니다. 먼저 매칭을 추가해 주세요.')),
                        );
                        return;
                      }
                      final success = appState.enterNextMatchToCourt(game.courtNumber);
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('제 ${game.courtNumber} 코트에 대기 1번 팀이 입장하여 게임이 시작되었습니다!'),
                            backgroundColor: Colors.green.shade700,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),

            const Divider(height: 16),

            // 코트 경기 내용 (선수 대진표)
            if (isIdle)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text(
                  hasWaitingMatch ? '코트가 비어있습니다. 우측 상단의 [입장 🚀]을 누르면 대기 1번 팀이 입장합니다.' : '현재 코트가 비어있습니다. 대기열에 매칭을 추가해 주세요.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              )
            else
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Team A',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                                  fontSize: 11,
                                ),
                              ),
                              if (isFinished)
                                const Text('종료', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...game.teamA.map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '${p.name} (${p.tier})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    decoration: isFinished ? TextDecoration.lineThrough : null,
                                    color: isFinished
                                        ? Colors.grey
                                        : (isDark ? Colors.white : Colors.black87),
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
                        color: isFinished ? Colors.grey : Colors.red.shade400,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  // Team B
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF4C1D24) : Colors.pink.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? Colors.pink.shade700 : Colors.pink.shade200,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Team B',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.pink.shade300 : Colors.pink.shade800,
                                  fontSize: 11,
                                ),
                              ),
                              if (isFinished)
                                const Text('종료', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...game.teamB.map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '${p.name} (${p.tier})',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    decoration: isFinished ? TextDecoration.lineThrough : null,
                                    color: isFinished
                                        ? Colors.grey
                                        : (isDark ? Colors.white : Colors.black87),
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

  // ==========================================
  // 제 4코트 레슨 전용 카드 (4코트 레슨 모드 활성화 시)
  // ==========================================
  Widget _buildLessonCourtCard(BuildContext context, GameMatch game, AppState appState, bool isDark) {
    final activeStudents = appState.activeLessonMembers;
    final waitingStudents = appState.waitingLessonMembers;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.amber.shade700 : Colors.amber.shade500,
          width: 1.5,
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
                        color: Colors.amber.shade800,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '제 4 코트 (레슨)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: activeStudents.isNotEmpty ? Colors.purple.shade600 : Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        activeStudents.isNotEmpty ? '레슨 진행중 🎾' : '레슨 대기 ⏳',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                Text(
                  '지도: ${appState.lessonCoach} 🏸',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text('🎾 현재 레슨 참여자:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            if (activeStudents.isEmpty)
              Text('현재 레슨 진행 중인 인원이 없습니다.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
            else
              Wrap(
                spacing: 6,
                children: activeStudents.map((s) => Chip(
                      label: Text('${s.name} (${s.tier})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.purple.shade50,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.hourglass_top, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  '레슨 대기 순번 (${waitingStudents.length}명 대기):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (waitingStudents.isEmpty)
              Text('레슨 대기자가 없습니다.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
            else
              Wrap(
                spacing: 6,
                children: waitingStudents.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final s = entry.value;
                  return Chip(
                    label: Text('${idx + 1}번: ${s.name}', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 수동 대기 매칭 추가 다이얼로그
  // ==========================================
  void _showManualMatchDialog(BuildContext context, AppState appState) {
    // 콕 제출한 오늘 참여자 중 선택 가능한 회원 목록
    final availableCandidates = appState.todayAttendees
        .where((m) => m.hasSubmittedShuttle && m.lessonStatus == 'none')
        .toList();

    if (availableCandidates.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수동 매칭을 위해 콕을 제출한 회원이 최소 4명 이상 필요합니다. (현재 콕 제출: ${availableCandidates.length}명)')),
      );
      return;
    }

    Member? pA1 = availableCandidates.isNotEmpty ? availableCandidates[0] : null;
    Member? pA2 = availableCandidates.length > 1 ? availableCandidates[1] : null;
    Member? pB1 = availableCandidates.length > 2 ? availableCandidates[2] : null;
    Member? pB2 = availableCandidates.length > 3 ? availableCandidates[3] : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final selectedIds = {pA1?.id, pA2?.id, pB1?.id, pB2?.id}.whereType<String>().toSet();
          final isComplete = selectedIds.length == 4;

          Widget buildPlayerDropdown(String label, Member? current, ValueChanged<Member?> onChanged) {
            return DropdownButtonFormField<String>(
              value: current?.id,
              decoration: InputDecoration(
                labelText: label,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: availableCandidates.map((m) {
                final isDuplicate = selectedIds.contains(m.id) && m.id != current?.id;
                return DropdownMenuItem<String>(
                  value: m.id,
                  enabled: !isDuplicate,
                  child: Text(
                    '${m.name} (${m.tier}조 / ${m.matchCountToday}경기)${isDuplicate ? ' (선택됨)' : ''}',
                    style: TextStyle(
                      color: isDuplicate ? Colors.grey : null,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val == null) return;
                final found = availableCandidates.firstWhere((m) => m.id == val);
                onChanged(found);
              },
            );
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.edit_note, color: Colors.indigo),
                SizedBox(width: 8),
                Text('수동 대기 매칭 편성', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Team A와 Team B에 출전할 4명의 선수를 지정합니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  const Text('Team A (2명):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                  const SizedBox(height: 6),
                  buildPlayerDropdown('Team A 선수 1', pA1, (m) => setDlgState(() => pA1 = m)),
                  const SizedBox(height: 8),
                  buildPlayerDropdown('Team A 선수 2', pA2, (m) => setDlgState(() => pA2 = m)),
                  const SizedBox(height: 14),
                  const Text('Team B (2명):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.pink)),
                  const SizedBox(height: 6),
                  buildPlayerDropdown('Team B 선수 1', pB1, (m) => setDlgState(() => pB1 = m)),
                  const SizedBox(height: 8),
                  buildPlayerDropdown('Team B 선수 2', pB2, (m) => setDlgState(() => pB2 = m)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: isComplete
                    ? () {
                        appState.addManualMatchToQueue(
                          teamA: [pA1!, pA2!],
                          teamB: [pB1!, pB2!],
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('수동 편성된 매칭이 대기열에 추가되었습니다!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    : null,
                child: const Text('대기열에 추가'),
              ),
            ],
          );
        },
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
}
