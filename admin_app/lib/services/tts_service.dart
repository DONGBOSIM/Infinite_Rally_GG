import 'package:flutter_tts/flutter_tts.dart';
import '../models/game_match.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  TtsService._internal() {
    _initTts();
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> _initTts() async {
    if (_isInitialized) return;
    try {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5); // 체육관 앰프용 또렷한 한국어 발음 속도
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
      });

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
      });

      _isInitialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('TTS 초기화 오류: $e');
    }
  }

  /// 사용자 지정 형식 안내 멘트 생성:
  /// 예: "1코트, 윤서브, 장스윙, 노크로스, 서하이 입장해주세요."
  String buildCallMessage(GameMatch game) {
    if (game.courtType == 'lesson') {
      if (game.lessonStudents.isNotEmpty) {
        final names = game.lessonStudents.map((s) => s.name).join(', ');
        return '${game.courtNumber}코트, $names 레슨 입장해주세요.';
      } else {
        return '${game.courtNumber}코트, 레슨 코트로 입장해주세요.';
      }
    }

    final players = [...game.teamA, ...game.teamB];
    if (players.isEmpty) {
      return '${game.courtNumber}코트 입장해주세요.';
    }
    final playerNames = players.map((p) => p.name).join(', ');
    return '${game.courtNumber}코트, $playerNames 입장해주세요.';
  }

  /// 단일 코트 음성 호명
  Future<void> speakCourt(GameMatch game) async {
    await _initTts();
    await _flutterTts.stop();
    final message = buildCallMessage(game);
    await _flutterTts.speak(message);
  }

  /// 전체 코트 순차 호명
  Future<void> speakAllCourts(List<GameMatch> games) async {
    await _initTts();
    await _flutterTts.stop();

    final activeGames = games.where((g) => g.status != 'finished').toList();
    if (activeGames.isEmpty) return;

    for (final game in activeGames) {
      final msg = buildCallMessage(game);
      await _flutterTts.speak(msg);
      // 코트 간 충분한 간격을 두고 순차 안내 (발화 완료 대기)
      await _flutterTts.awaitSpeakCompletion(true);
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  /// 음성 안내 중지
  Future<void> stop() async {
    _isSpeaking = false;
    await _flutterTts.stop();
  }
}

