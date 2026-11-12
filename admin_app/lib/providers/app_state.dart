import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/member.dart';
import '../models/game_match.dart';
import '../models/daily_session.dart';
import '../services/matching_service.dart';
import '../services/firestore_service.dart';

class AppState extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  List<Member> _members = [];
  int _courtCount = 4;
  List<GameMatch> _currentGames = [];
  List<Map<String, dynamic>> _upcomingGames = [];
  String _notice = "경기 종료 후 셔틀콕은 코트 옆 바구니에 넣어주세요.";
  String _webViewerUrl = "https://infinite-rally-gg.web.app/";
  bool _isUploading = false;
  String? _lastUploadMessage;

  AppState() {
    _initSampleMembers();
  }

  // Getters
  List<Member> get members => _members;
  int get courtCount => _courtCount;
  List<GameMatch> get currentGames => _currentGames;
  List<Map<String, dynamic>> get upcomingGames => _upcomingGames;
  String get notice => _notice;
  String get webViewerUrl => _webViewerUrl;
  bool get isUploading => _isUploading;
  String? get lastUploadMessage => _lastUploadMessage;

  int get presentCount => _members.where((m) => m.isPresent).length;

  void setCourtCount(int count) {
    if (count > 0 && count <= 10) {
      _courtCount = count;
      notifyListeners();
    }
  }

  void setNotice(String newNotice) {
    _notice = newNotice;
    notifyListeners();
  }

  void setWebViewerUrl(String url) {
    _webViewerUrl = url;
    notifyListeners();
  }

  // 회원 출석 토글
  void toggleAttendance(String memberId) {
    final index = _members.indexWhere((m) => m.id == memberId);
    if (index != -1) {
      _members[index].isPresent = !_members[index].isPresent;
      notifyListeners();
    }
  }

  // 전체 출석 처리 / 전체 해제
  void setAllAttendance(bool present) {
    for (final member in _members) {
      member.isPresent = present;
    }
    notifyListeners();
  }

  // 회원 추가
  void addMember(Member member) {
    _members.add(member);
    notifyListeners();
  }

  // 회원 삭제
  void removeMember(String memberId) {
    _members.removeWhere((m) => m.id == memberId);
    notifyListeners();
  }

  // 경기 수 초기화
  void resetMatchCounts() {
    for (final member in _members) {
      member.matchCountToday = 0;
    }
    notifyListeners();
  }

  // 자동 공평 매칭 생성
  void generateMatches() {
    final result = MatchingService.generateBalancedMatches(
      members: _members,
      courtCount: _courtCount,
    );
    _currentGames = result.currentGames;
    _upcomingGames = result.upcomingGames;
    notifyListeners();
  }

  // 특정 코트 경기 완료 처리 (해당 선수들의 matchCountToday 증가)
  void finishGame(int courtNumber) {
    final gameIndex = _currentGames.indexWhere((g) => g.courtNumber == courtNumber);
    if (gameIndex != -1) {
      final game = _currentGames[gameIndex];
      game.status = 'finished';

      // 참여 선수 4명 경기 수 1 증가
      final playerIds = [
        ...game.teamA.map((p) => p.id),
        ...game.teamB.map((p) => p.id),
      ];

      for (final id in playerIds) {
        final memberIndex = _members.indexWhere((m) => m.id == id);
        if (memberIndex != -1) {
          _members[memberIndex].matchCountToday++;
        }
      }

      notifyListeners();
    }
  }

  // Firestore에 오늘 매칭 데이터 업로드
  Future<bool> uploadToFirestore() async {
    _isUploading = true;
    _lastUploadMessage = null;
    notifyListeners();

    if (!_firestoreService.isFirebaseAvailable) {
      _isUploading = false;
      _lastUploadMessage = "Firebase 연동 전입니다 (로컬 매칭 및 QR 코드는 정상 이용 가능합니다).";
      notifyListeners();
      return false;
    }

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final activeCourts = List.generate(_courtCount, (index) => index + 1);

    final session = DailySession(
      sessionDate: todayStr,
      title: "무한랠리 ${DateFormat('M월 d일').format(DateTime.now())} 정기모임",
      activeCourts: activeCourts,
      currentGames: _currentGames,
      upcomingGames: _upcomingGames,
      notice: _notice,
      updatedAt: DateTime.now(),
    );

    final success = await _firestoreService.uploadDailySession(session);
    _isUploading = false;
    _lastUploadMessage = success ? "성공적으로 DB에 업로드되었습니다!" : "업로드 실패: 네트워크 또는 Firebase 설정을 확인해주세요.";
    notifyListeners();

    return success;
  }

  // 50명 샘플 회원 초기화 (테스트용)
  void _initSampleMembers() {
    final sampleNames = [
      "김랠리", "이민턴", "박스매시", "최헤어핀", "정클리어", "강드라이브", "윤서브", "송푸시",
      "한콕", "오네트", "문드롭", "신앤드", "백언더", "유서브", "서하이", "권로브",
      "배풋워크", "조슬라이딩", "장스윙", "임스트록", "하리시브", "노크로스", "양탑", "손프론트",
      "고백핸드", "엄라켓", "홍거트", "안그립", "황엔드", "차파트너", "구경기", "전포핸드",
      "심토너먼트", "탁심판", "문승리", "표파이팅", "남점수", "도에이스", "주콕콕", "방스텝",
      "선동작", "석각도", "원자세", "설파워", "천스피드", "지탄력", "명수비", "채공격",
      "우집중", "육체력"
    ];

    final tiers = ["A", "B", "C", "D", "초심"];
    final genders = ["M", "F"];

    _members = List.generate(sampleNames.length, (index) {
      final tier = tiers[index % tiers.length];
      final gender = genders[index % genders.length];
      // 앞쪽 24명은 기본 출석 상태로 설정
      final isPresent = index < 24;

      return Member(
        id: "user_${(index + 1).toString().padLeft(3, '0')}",
        name: sampleNames[index],
        tier: tier,
        gender: gender,
        isPresent: isPresent,
        matchCountToday: 0,
      );
    });
  }
}
