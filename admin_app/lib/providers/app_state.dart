import 'dart:async';
import 'package:flutter/material.dart';
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

  // Phase 1 확장: 테마 모드 & 레슨 코트 & 다중 관리자 동기화
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLessonCourtEnabled = true; // 4코트 레슨 모드 활성화 여부
  String _lessonCoach = "코치님";
  List<Map<String, dynamic>> _lessonQueue = [];
  StreamSubscription<DailySession?>? _sessionSubscription;
  bool _isRemoteSyncActive = false;
  bool _isLoadingMasterMembers = false;

  AppState() {
    _initSampleMembers();
    loadMasterMembers();
    initRealtimeSync();
  }

  // Getters
  List<Member> get members => _members;
  // ⭐️ 정식 회원만 반환 (게스트 제외)
  List<Member> get regularMembers => _members.where((m) => !m.isGuest).toList();
  int get regularMemberCount => _members.where((m) => !m.isGuest).length;
  // 오늘 참석한 게스트 목록
  List<Member> get todayGuests => _members.where((m) => m.isPresent && m.isGuest).toList();
  int get todayGuestCount => _members.where((m) => m.isPresent && m.isGuest).length;

  int get courtCount => _courtCount;
  List<GameMatch> get currentGames => _currentGames;
  List<Map<String, dynamic>> get upcomingGames => _upcomingGames;
  String get notice => _notice;
  String get webViewerUrl => _webViewerUrl;
  bool get isUploading => _isUploading;
  String? get lastUploadMessage => _lastUploadMessage;
  ThemeMode get themeMode => _themeMode;
  bool get isLessonCourtEnabled => _isLessonCourtEnabled;
  bool get isLoadingMasterMembers => _isLoadingMasterMembers;
  String get lessonCoach => _lessonCoach;
  List<Map<String, dynamic>> get lessonQueue => _lessonQueue;
  bool get isRemoteSyncActive => _isRemoteSyncActive;

  int get presentCount => _members.where((m) => m.isPresent).length;
  List<Member> get todayAttendees => _members.where((m) => m.isPresent).toList();
  int get submittedShuttleCount => _members.where((m) => m.isPresent && m.hasSubmittedShuttle).length;
  int get lessonCount => _members.where((m) => m.isPresent && m.isLessonAny).length;
  int get activeLessonCount => _members.where((m) => m.isPresent && m.lessonStatus == 'active').length;
  int get waitingLessonCount => _members.where((m) => m.isPresent && m.lessonStatus == 'waiting').length;
  int get matchEligibleCount => _members.where((m) => m.isPresent && m.hasSubmittedShuttle && m.lessonStatus == 'none').length;
  List<Member> get activeLessonMembers => _members.where((m) => m.isPresent && m.lessonStatus == 'active').toList();
  List<Member> get waitingLessonMembers => _members.where((m) => m.isPresent && m.lessonStatus == 'waiting').toList();

  void _syncLessonQueue() {
    _lessonQueue = _members
        .where((m) => m.isPresent && m.lessonStatus == 'waiting')
        .map((m) => {
              'id': m.id,
              'name': m.name,
              'tier': m.tier,
              'gender': m.gender,
            })
        .toList();
  }

  // 테마 모드 순환 (시스템 모드 -> 라이트 모드 -> 다크 모드 -> 시스템 모드)
  String cycleTheme() {
    if (_themeMode == ThemeMode.system) {
      _themeMode = ThemeMode.light;
      notifyListeners();
      return '라이트 모드로 전환되었습니다.';
    } else if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
      notifyListeners();
      return '다크 모드로 전환되었습니다.';
    } else {
      _themeMode = ThemeMode.system;
      notifyListeners();
      return '시스템 설정(자동) 모드로 전환되었습니다.';
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  String get themeModeDescription {
    switch (_themeMode) {
      case ThemeMode.light:
        return '라이트 모드';
      case ThemeMode.dark:
        return '다크 모드';
      case ThemeMode.system:
      default:
        return '시스템 설정';
    }
  }

  // 4코트 레슨 모드 토글
  void toggleLessonCourt(bool enabled) {
    _isLessonCourtEnabled = enabled;
    notifyListeners();
  }

  void setLessonCoach(String coachName) {
    _lessonCoach = coachName;
    notifyListeners();
  }

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

  // 다중 관리자 실시간 양방향 동기화 리스너
  void initRealtimeSync() {
    if (!_firestoreService.isFirebaseAvailable) return;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _sessionSubscription?.cancel();

    _sessionSubscription = _firestoreService.listenDailySession(todayStr).listen((session) {
      if (session == null || _isUploading) return;

      _isRemoteSyncActive = true;
      _currentGames = session.currentGames;
      _upcomingGames = session.upcomingGames;
      _notice = session.notice;
      _isLessonCourtEnabled = session.isLessonCourtEnabled;
      _lessonCoach = session.lessonCoach;
      _lessonQueue = session.lessonQueue;

      // 원격에 회원 목록이 있으면 로컬 회원 출석/경기 수 상태 동기화
      if (session.members.isNotEmpty) {
        for (final remoteM in session.members) {
          final idx = _members.indexWhere((m) => m.id == remoteM.id);
          if (idx != -1) {
            _members[idx].isPresent = remoteM.isPresent;
            _members[idx].matchCountToday = remoteM.matchCountToday;
            _members[idx].hasSubmittedShuttle = remoteM.hasSubmittedShuttle;
            _members[idx].lessonStatus = remoteM.lessonStatus;
            _members[idx].fixedPartnerId = remoteM.fixedPartnerId;
          } else {
            _members.add(remoteM);
          }
        }
      }

      notifyListeners();
    });
  }

  // 회원 출석 토글
  void toggleAttendance(String memberId) {
    final index = _members.indexWhere((m) => m.id == memberId);
    if (index != -1) {
      _members[index].isPresent = !_members[index].isPresent;
      if (!_members[index].isPresent) {
        // 불참 처리 시 콕 제출 및 레슨 상태도 초기화
        _members[index].hasSubmittedShuttle = false;
        _members[index].lessonStatus = 'none';
      }
      _syncLessonQueue();
      notifyListeners();
    }
  }

  // 콕 제출(출석 확정) 토글 - 누른 회원만 출석자로 게임 매칭 풀에 포함됨
  void toggleShuttleSubmission(String memberId) {
    final index = _members.indexWhere((m) => m.id == memberId);
    if (index != -1) {
      _members[index].hasSubmittedShuttle = !_members[index].hasSubmittedShuttle;
      // 콕 제출 시 자동으로 출석 처리
      if (_members[index].hasSubmittedShuttle) {
        _members[index].isPresent = true;
      }
      notifyListeners();
    }
  }

  // 레슨 신청 상태 3단계 순환 (없음 none -> 레슨 대기 waiting -> 레슨 진행 active -> 없음 none)
  void cycleLessonStatus(String memberId) {
    final index = _members.indexWhere((m) => m.id == memberId);
    if (index != -1) {
      final current = _members[index].lessonStatus;
      if (current == 'none') {
        _members[index].lessonStatus = 'waiting';
      } else if (current == 'waiting') {
        _members[index].lessonStatus = 'active';
      } else {
        _members[index].lessonStatus = 'none';
      }
      _syncLessonQueue();
      notifyListeners();
    }
  }

  // 하위 호환용 toggleLesson
  void toggleLesson(String memberId) => cycleLessonStatus(memberId);

  // 게스트 간편 수동 추가 (자동 G 접두사 부여 및 당일 참석자로 등록)
  void addGuest({
    required String name,
    required String tier,
    required String gender,
    bool hasSubmittedShuttle = false,
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final formattedName = cleanName.startsWith('G ') ? cleanName : 'G $cleanName';
    final newGuest = Member(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      name: formattedName,
      tier: tier,
      gender: gender,
      isPresent: true,
      hasSubmittedShuttle: hasSubmittedShuttle,
      isGuest: true,
    );
    _members.add(newGuest);
    notifyListeners();
  }

  // 고정 페어(파트너) 설정: 상호 파트너 연결
  void setFixedPartner(String memberId1, String memberId2) {
    if (memberId1 == memberId2) return;
    final idx1 = _members.indexWhere((m) => m.id == memberId1);
    final idx2 = _members.indexWhere((m) => m.id == memberId2);

    if (idx1 != -1 && idx2 != -1) {
      // 기존에 맺어져 있던 파트너가 있다면 해제
      clearFixedPartner(memberId1);
      clearFixedPartner(memberId2);

      _members[idx1].fixedPartnerId = memberId2;
      _members[idx2].fixedPartnerId = memberId1;
      notifyListeners();
    }
  }

  // 고정 페어(파트너) 해제
  void clearFixedPartner(String memberId) {
    final idx = _members.indexWhere((m) => m.id == memberId);
    if (idx != -1) {
      final oldPartnerId = _members[idx].fixedPartnerId;
      _members[idx].fixedPartnerId = null;

      if (oldPartnerId != null && oldPartnerId.isNotEmpty) {
        final pIdx = _members.indexWhere((m) => m.id == oldPartnerId);
        if (pIdx != -1) {
          _members[pIdx].fixedPartnerId = null;
        }
      }
      notifyListeners();
    }
  }

  // 특정 회원의 고정 파트너 Member 객체 반환
  Member? getFixedPartner(String memberId) {
    final idx = _members.indexWhere((m) => m.id == memberId);
    if (idx != -1) {
      final partnerId = _members[idx].fixedPartnerId;
      if (partnerId != null && partnerId.isNotEmpty) {
        final pIdx = _members.indexWhere((m) => m.id == partnerId);
        if (pIdx != -1) return _members[pIdx];
      }
    }
    return null;
  }

  // OCR 투표 캡처 결과 일괄 적용 (기존 회원 출석 처리 + 게스트 일괄 등록)
  void applyOcrBatch({
    required List<String> memberIds,
    required List<String> newGuestNames,
    Map<String, String>? guestGenders,
    String defaultGuestTier = 'C',
    bool defaultSubmitShuttle = false,
  }) {
    // 1. 기존 회원 참석 처리 (오늘 참여자로 포함)
    for (final id in memberIds) {
      final idx = _members.indexWhere((m) => m.id == id);
      if (idx != -1) {
        _members[idx].isPresent = true;
        if (defaultSubmitShuttle) {
          _members[idx].hasSubmittedShuttle = true;
        }
      }
    }

    // 2. 신규 게스트 등록 (오늘 참여자로 등록, 사진에서 파싱된 성별 반영)
    for (final gName in newGuestNames) {
      final trimmed = gName.trim();
      if (trimmed.isNotEmpty) {
        final gender = guestGenders?[trimmed] ?? 'M';
        addGuest(
          name: trimmed,
          tier: defaultGuestTier,
          gender: gender,
          hasSubmittedShuttle: defaultSubmitShuttle,
        );
      }
    }

    notifyListeners();
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

  // 회원 정보 업데이트
  void updateMember(Member updated) {
    final index = _members.indexWhere((m) => m.id == updated.id);
    if (index != -1) {
      _members[index] = updated;
      notifyListeners();
    }
  }

  // 회원 삭제
  void removeMember(String memberId) {
    _members.removeWhere((m) => m.id == memberId);
    notifyListeners();
  }

  // 전체 회원 명부 초기화 (일괄 삭제)
  void clearAllMembers() {
    _members.clear();
    _currentGames.clear();
    _upcomingGames.clear();
    _lessonQueue.clear();
    notifyListeners();
  }

  // 시트(엑셀/구글시트 텍스트 복사본 또는 CSV)로부터 회원 일괄 등록
  int importMembersFromText(String rawText, {bool replaceAll = false}) {
    final lines = rawText.split('\n');
    final validTiers = {'S', 'A', 'B', 'C', 'D', 'E'};
    final newMembers = <Member>[];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // 탭(\t), 쉼표(,), 슬래시(/), 파이프(|) 구분자 분리
      List<String> tokens;
      if (line.contains('\t')) {
        tokens = line.split('\t');
      } else if (line.contains(',')) {
        tokens = line.split(',');
      } else if (line.contains('|')) {
        tokens = line.split('|');
      } else {
        tokens = line.split(RegExp(r'\s+'));
      }

      tokens = tokens.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) continue;

      final name = tokens[0];
      // 헤더 행 자동 감지 및 제외
      if (name == '이름' || name == '성명' || name.toLowerCase() == 'name') {
        continue;
      }

      // 급수 판별
      String tier = 'C';
      if (tokens.length >= 2) {
        final rawTier = tokens[1].toUpperCase().replaceAll('조', '');
        if (validTiers.contains(rawTier)) {
          tier = rawTier;
        } else if (rawTier.contains('초심')) {
          tier = 'E';
        }
      }

      // 성별 판별
      String gender = 'M';
      if (tokens.length >= 3) {
        final rawGender = tokens[2].toUpperCase();
        if (rawGender == 'F' || rawGender == '여' || rawGender == '여성' || rawGender == 'W') {
          gender = 'F';
        }
      }

      final id = "user_${DateTime.now().microsecondsSinceEpoch}_${newMembers.length + 1}";
      newMembers.add(Member(
        id: id,
        name: name,
        tier: tier,
        gender: gender,
        isPresent: false,
        matchCountToday: 0,
      ));
    }

    if (newMembers.isEmpty) return 0;

    if (replaceAll) {
      _members = newMembers;
      _currentGames.clear();
      _upcomingGames.clear();
      _lessonQueue.clear();
    } else {
      // 기존 명단 유지하고 중복되지 않은 이름만 추가
      for (final m in newMembers) {
        if (!_members.any((existing) => existing.name == m.name)) {
          _members.add(m);
        }
      }
    }

    notifyListeners();
    return newMembers.length;
  }

  // 경기 수 초기화
  void resetMatchCounts() {
    for (final member in _members) {
      member.matchCountToday = 0;
    }
    notifyListeners();
  }

  // 자동 공평 매칭 생성 (콕 제출 출석자만 매칭, 4코트 레슨 시 레슨자 전용 코트 구성)
  void generateMatches() {
    _syncLessonQueue();
    final result = MatchingService.generateBalancedMatches(
      members: _members,
      courtCount: _courtCount,
      isLessonCourtEnabled: _isLessonCourtEnabled,
      lessonCoach: _lessonCoach,
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

      if (game.courtType == 'lesson') {
        // 레슨 참여자 경기 수 1 증가
        for (final student in game.lessonStudents) {
          final mIdx = _members.indexWhere((m) => m.id == student.id);
          if (mIdx != -1) {
            _members[mIdx].matchCountToday++;
          }
        }
      } else {
        // 일반 복식 경기 참여 선수 4명 경기 수 1 증가
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
      }

      notifyListeners();
    }
  }

  // 영구 마스터 회원 명부 로드 (0원 무과금 최적화: 읽기 1회)
  Future<void> loadMasterMembers() async {
    if (!_firestoreService.isFirebaseAvailable) return;
    _isLoadingMasterMembers = true;
    notifyListeners();

    try {
      final remoteList = await _firestoreService.fetchMasterMembers();
      if (remoteList != null && remoteList.isNotEmpty) {
        // 원격 마스터 명단 정제 (혹시 기존에 저장된 게스트가 있다면 완전히 제외)
        final cleanRemoteList = remoteList.where((m) => !m.isGuest && !m.name.startsWith('G ')).toList();
        // 원격 마스터 명단으로 교체하되, 현재 메모리의 출석/경기 수 상태가 있다면 보존
        final merged = <Member>[];
        for (final remoteM in cleanRemoteList) {
          final localIdx = _members.indexWhere((m) => m.id == remoteM.id);
          if (localIdx != -1) {
            remoteM.isPresent = _members[localIdx].isPresent;
            remoteM.hasSubmittedShuttle = _members[localIdx].hasSubmittedShuttle;
            remoteM.matchCountToday = _members[localIdx].matchCountToday;
            remoteM.lessonStatus = _members[localIdx].lessonStatus;
            remoteM.fixedPartnerId = _members[localIdx].fixedPartnerId;
          }
          merged.add(remoteM);
        }
        // 당일 등록된 게스트가 있다면 보존
        for (final localM in _members) {
          if (localM.isGuest && !merged.any((m) => m.id == localM.id)) {
            merged.add(localM);
          }
        }
        _members = merged;
      }
    } catch (e) {
      // ignore: avoid_print
      print('loadMasterMembers Error: $e');
    } finally {
      _isLoadingMasterMembers = false;
      notifyListeners();
    }
  }

  // Firestore에 오늘 매칭 데이터 및 영구 마스터 회원 명부 원스톱 업로드 (0원 무과금 최적화: 쓰기 각 1회)
  Future<bool> syncAllToCloud() async {
    _syncLessonQueue();
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
      isLessonCourtEnabled: _isLessonCourtEnabled,
      lessonCoach: _lessonCoach,
      lessonQueue: _lessonQueue,
      members: _members,
    );

    // 당일 세션과 영구 마스터 회원 명부를 원스톱으로 저장
    final sessionSuccess = await _firestoreService.uploadDailySession(session);
    // ⭐️ 영구 마스터 회원 DB에는 게스트를 100% 제외하고 순수 정식 회원만 영구 보존!
    final regularMembersOnly = regularMembers;
    final masterSuccess = await _firestoreService.saveMasterMembers(regularMembersOnly);

    final success = sessionSuccess && masterSuccess;
    _isUploading = false;
    _lastUploadMessage = success
        ? "회원 명부 및 경기 매칭이 클라우드에 성공적으로 동기화되었습니다!"
        : (sessionSuccess
            ? "세션은 동기화되었으나 회원 명부 저장을 확인해주세요."
            : "업로드 실패: 네트워크 또는 Firebase 설정을 확인해주세요.");
    notifyListeners();

    return success;
  }

  // 하위 호환용 uploadToFirestore
  Future<bool> uploadToFirestore() => syncAllToCloud();

  // S, A, B, C, D, E 6단계 급수 샘플 회원 초기화 (50명)
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

    final tiers = ["S", "A", "B", "C", "D", "E"];
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
        hasSubmittedShuttle: isPresent,
        matchCountToday: 0,
      );
    });
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }
}
