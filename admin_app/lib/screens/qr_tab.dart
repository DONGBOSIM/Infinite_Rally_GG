import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/app_state.dart';

class QrTab extends StatelessWidget {
  const QrTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final webUrl = appState.webViewerUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 안내용 QR 코드'),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '웹페이지 접속 URL 수정',
            onPressed: () => _showEditUrlDialog(context, appState),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          children: [
            const Text(
              '🏸 무한랠리 실시간 매칭표 접속',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '동호회 회원들에게 이 화면을 보여주세요.\n스마트폰 기본 카메라로 비추면 바로 웹페이지로 이동합니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 24),

            // QR 코드 카드
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: webUrl,
                  version: QrVersions.auto,
                  size: 260.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F172A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 현재 연결된 웹 URL 박스
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      webUrl,
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'URL 복사',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: webUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('접속 URL이 클립보드에 복사되었습니다.')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('GitHub Pages 배포 URL 설정'),
              onPressed: () => _showEditUrlDialog(context, appState),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUrlDialog(BuildContext context, AppState appState) {
    final ctrl = TextEditingController(text: appState.webViewerUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원용 웹페이지 URL 설정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GitHub Pages로 배포된 web_viewer의 웹 주소를 입력하세요:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'https://<username>.github.io/<repo>/web_viewer/',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                appState.setWebViewerUrl(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

