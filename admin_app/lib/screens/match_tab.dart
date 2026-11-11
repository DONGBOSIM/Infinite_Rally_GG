import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class MatchTab extends StatelessWidget {
  const MatchTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentGames = appState.currentGames;
    final upcomingGames = appState.upcomingGames;

    return Scaffold(
      appBar: AppBar(
        title: const Text('게임 매칭 및 코트 관리'),
        elevation: 1,
        actions: [
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
                    const Divider(height: 16),
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
                              if (appState.presentCount < 4) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('참석 회원이 4명 이상이어야 매칭이 가능합니다.')),
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
                    '총 출전: ${currentGames.length * 4}명',
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
                  color: Colors.grey.shade100,
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
                                ],
                              ),
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
                          const Divider(height: 16),
                          Row(
                            children: [
                              // Team A
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Team A', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      ...game.teamA.map((p) => Text('${p.name} (${p.tier})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('VS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                              ),
                              // Team B
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Team B', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink, fontSize: 11)),
                                      const SizedBox(height: 4),
                                      ...game.teamB.map((p) => Text('${p.name} (${p.tier})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
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
                    color: Colors.grey.shade50,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.grey.shade400,
                        child: Text('${wait['order']}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                      title: Text(
                        '${(wait['teamA'] as List).join(', ')}  VS  ${(wait['teamB'] as List).join(', ')}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      trailing: Text(
                        '${wait['designatedCourt']}코트 예정',
                        style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
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
}

