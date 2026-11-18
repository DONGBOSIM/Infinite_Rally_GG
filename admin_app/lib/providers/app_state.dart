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
  final List<GameMatch> _waitingQueue = []; // ⭐️ 대기열 큐 (GameMatch 객체 기반)
  String _notice = "경기 종료 후 셔틀콕은 코트 옆 바구니에 넣어주세요.";
  String _webViewerUrl = "https://infinite-rally-gg.web.app/";
  bool _isUploading = false;
  String? _lastUploadMessage;

  // Phase 1 확장: 테마 모드 & 레슨 코트 & 다중 관리자 동기화
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLessonCourtEnabled = true; // 4코트 레슨 모드 활성화 여부
  String _lessonCoach = "무한랠리도우미";
  List<Map<String, dynamic>> _lessonQueue = [];
  StreamSubscription<DailySession?>? _sessionSubscription;
  bool _isRemoteSyncActive = false;
  bool _isLoadingMasterMembers = false;

  AppState() {
    _initSampleMembers();
    loadMasterMembers();
    ensureCourtsExist();
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

  // ⭐️ 대기열 큐 Getters (웹 뷰어 및 Firestore 100% 호환 Map 변환)
  List<Map<String, dynamic>> get upcomingGames {
    return _waitingQueue.asMap().entries.map((entry) {
      final idx = entry.key;
      final match = entry.value;
      return {
        'id': match.gameId,
        'order': idx + 1,
        'designatedCourt': ((idx) % (_courtCount > 0 ? _courtCount : 1)) + 1,
        'teamA': match.teamA.map((m) => '${m.name} (${m.tier})').toList(),
        'teamB': match.teamB.map((m) => '${m.name} (${m.tier})').toList(),
        'teamAPlayers': match.teamA.map((m) => m.toMap()).toList(),
        'teamBPlayers': match.teamB.map((m) => m.toMap()).toList(),
        'isFixedPair': match.isFixedPair,
      };
    }).toList();
  }

  List<GameMatch> get waitingQueue => _waitingQueue;
  int get waitingQueueCount => _waitingQueue.length;
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

    // ⭐️ 레슨 진행 중인 인원(_members 중 active)을 _currentGames의 레슨 코트(제4코트)에 실시간 자동 동기화
    final activeStudents = activeLessonMembers;
    for (final game in _currentGames) {
      if (game.courtType == 'lesson') {
        game.lessonStudents = List<Member>.from(activeStudents);
        game.lessonCoach = _lessonCoach;
      }
    }
  }

  void _syncWaitingQueueFromRemote(List<Map<String, dynamic>> remoteList) {
    _waitingQueue.clear();
    for (final map in remoteList) {
      final teamAPlayers = (map['teamAPlayers'] as List?)?.map((p) => Member.fromMap(Map<String, dynamic>.from(p))).toList() ?? [];
      final teamBPlayers = (map['teamBPlayers'] as List?)?.map((p) => Member.fromMap(Map<String, dynamic>.from(p))).toList() ?? [];

      if (teamAPlayers.isEmpty && map['teamA'] is List) {
        for (final nameStr in map['teamA']) {
          final cleanName = nameStr.toString().split(' ')[0];
          final m = _members.firstWhere(
            (mem) => mem.name == cleanName,
            orElse: () => Member(id: 'guest_${cleanName.hashCode}', name: cleanName, tier: 'C', gender: 'M'),
          );
          teamAPlayers.add(m);
        }
      }
      if (teamBPlayers.isEmpty && map['teamB'] is List) {
        for (final nameStr in map['teamB']) {
          final cleanName = nameStr.toString().split(' ')[0];
          final m = _members.firstWhere(
            (mem) => mem.name == cleanName,
            orElse: () => Member(id: 'guest_${cleanName.hashCode}', name: cleanName, tier: 'C', gender: 'M'),
          );
          teamBPlayers.add(m);
        }
      }

      _waitingQueue.add(GameMatch(
        courtNumber: 0,
        gameId: map['id'] ?? map['gameId'] ?? 'wait_${_waitingQueue.length}',
        teamA: teamAPlayers,
        teamB: teamBPlayers,
        status: 'waiting',
        startTime: '',
        isFixedPair: map['isFixedPair'] ?? false,
      ));
    }
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
    ensureCourtsExist();
    notifyListeners();
  }

  void setLessonCoach(String coachName) {
    _lessonCoach = coachName;
    ensureCourtsExist();
    notifyListeners();
  }

  void setCourtCount(int count) {
    if (count > 0 && count <= 10) {
      _courtCount = count;
      ensureCourtsExist();
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
      _syncWaitingQueueFromRemote(session.upcomingGames);
      _notice = session.notice;
      _isLessonCourtEnabled = session.isLessonCourtEnabled;
      _lessonCoach = (session.lessonCoach == '코치님' || session.lessonCoach.isEmpty) ? '무한랠리도우미' : session.lessonCoach;
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
    _waitingQueue.clear();
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
      _waitingQueue.clear();
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

  // ⭐️ 현재 코트 게임 중이거나 대기열에 있지 않은, 즉시 대기 매칭 가능한 인원 목록
  List<Member> get availableMembersForQueue {
    final busyIds = <String>{};

    // 1. 코트에서 게임 진행 중인 인원 (게임중... 상태)
    for (final game in _currentGames) {
      if (game.status == 'in_progress') {
        if (game.courtType == 'lesson') {
          busyIds.addAll(game.lessonStudents.map((s) => s.id));
        } else {
          busyIds.addAll(game.teamA.map((m) => m.id));
          busyIds.addAll(game.teamB.map((m) => m.id));
        }
      }
    }

    // 2. 대기열에 이미 편성된 인원
    for (final match in _waitingQueue) {
      busyIds.addAll(match.teamA.map((m) => m.id));
      busyIds.addAll(match.teamB.map((m) => m.id));
    }

    return _members.where((m) =>
        m.isPresent &&
        m.hasSubmittedShuttle &&
        m.lessonStatus == 'none' &&
        !busyIds.contains(m.id)).toList();
  }

  // 1~courtCount 코트 슬롯 보장 (비어있는 코트는 idle)
  void ensureCourtsExist() {
    final existingNumbers = _currentGames.map((g) => g.courtNumber).toSet();
    for (int i = 1; i <= _courtCount; i++) {
      if (!existingNumbers.contains(i)) {
        final isLesson = _isLessonCourtEnabled && i == 4 && _courtCount >= 4;
        _currentGames.add(GameMatch(
          courtNumber: i,
          gameId: 'idle_$i',
          teamA: [],
          teamB: [],
          status: 'idle',
          startTime: '',
          courtType: isLesson ? 'lesson' : 'game',
          lessonCoach: isLesson ? _lessonCoach : '',
        ));
      }
    }
    // 레슨 모드 여부 업데이트
    for (final game in _currentGames) {
      if (game.courtNumber == 4 && _courtCount >= 4) {
        if (_isLessonCourtEnabled && game.courtType != 'lesson') {
          game.courtType = 'lesson';
          game.lessonCoach = _lessonCoach;
          game.lessonStudents = List<Member>.from(activeLessonMembers);
        } else if (!_isLessonCourtEnabled && game.courtType == 'lesson') {
          game.courtType = 'game';
          game.lessonStudents = [];
        }
      }
    }
    _syncLessonQueue();
    _currentGames.sort((a, b) => a.courtNumber.compareTo(b.courtNumber));
    _currentGames.removeWhere((g) => g.courtNumber > _courtCount);
  }

  // ⭐️ [공평 자동 매칭 생성] -> 코트의 진행 중 게임을 절대 건드리지 않고 '대기열(Queue)'에 추가!
  int addAutoMatchesToQueue() {
    _syncLessonQueue();
    final availables = availableMembersForQueue;
    if (availables.length < 4) return 0;

    final newMatches = MatchingService.createBalancedMatchesForQueue(availables);
    if (newMatches.isEmpty) return 0;

    _waitingQueue.addAll(newMatches);
    notifyListeners();
    return newMatches.length;
  }

  // 하위 호환용 generateMatches
  void generateMatches() => addAutoMatchesToQueue();

  // ⭐️ [수동 대기 매칭 추가] -> 관리자가 직접 선택한 4인 팀을 대기열 끝에 등록
  void addManualMatchToQueue({
    required List<Member> teamA,
    required List<Member> teamB,
  }) {
    final newMatch = GameMatch(
      courtNumber: 0,
      gameId: "manual_${DateTime.now().millisecondsSinceEpoch}",
      teamA: teamA,
      teamB: teamB,
      status: 'waiting',
      startTime: DateFormat('HH:mm').format(DateTime.now()),
      isFixedPair: false,
    );
    _waitingQueue.add(newMatch);
    notifyListeners();
  }

  // 대기열 항목 삭제
  void removeQueueItem(int index) {
    if (index >= 0 && index < _waitingQueue.length) {
      _waitingQueue.removeAt(index);
      notifyListeners();
    }
  }

  // 대기열 항목 순서 변경 (위/아래)
  void moveQueueItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _waitingQueue.length) return;
    if (newIndex < 0 || newIndex >= _waitingQueue.length) return;
    final item = _waitingQueue.removeAt(oldIndex);
    _waitingQueue.insert(newIndex, item);
    notifyListeners();
  }

  // ⭐️ 코트 라이프사이클 1단계: [게임 종료] (in_progress -> finished)
  void finishGame(int courtNumber) {
    final gameIndex = _currentGames.indexWhere((g) => g.courtNumber == courtNumber);
    if (gameIndex != -1) {
      final game = _currentGames[gameIndex];
      if (game.status != 'in_progress') return; // 이미 종료된 상태면 중복 반영 방지

      // ⭐️ 상태 변경: 게임 종료
      game.status = 'finished';

      if (game.courtType == 'lesson') {
        for (final student in game.lessonStudents) {
          final mIdx = _members.indexWhere((m) => m.id == student.id);
          if (mIdx != -1) _members[mIdx].matchCountToday++;
        }
      } else {
        final playerIds = [
          ...game.teamA.map((p) => p.id),
          ...game.teamB.map((p) => p.id),
        ];
        for (final id in playerIds) {
          final memberIndex = _members.indexWhere((m) => m.id == id);
          if (memberIndex != -1) _members[memberIndex].matchCountToday++;
        }
      }

      notifyListeners();
    }
  }

  // ⭐️ 코트 라이프사이클 2단계: [입장] (대기 1번 팀 입장 -> in_progress로 전이, 대기열 순번 자동 전진)
  bool enterNextMatchToCourt(int courtNumber) {
    if (_waitingQueue.isEmpty) return false;

    // 대기 1번 매칭 인출 (순번 하나씩 앞으로 당겨짐)
    final nextMatch = _waitingQueue.removeAt(0);
    final nowStr = DateFormat('HH:mm').format(DateTime.now());

    final enteredGame = GameMatch(
      courtNumber: courtNumber,
      gameId: nextMatch.gameId.isNotEmpty ? nextMatch.gameId : 'match_${DateTime.now().millisecondsSinceEpoch}',
      teamA: nextMatch.teamA,
      teamB: nextMatch.teamB,
      status: 'in_progress', // ⭐️ 코트 상태: 게임중...
      startTime: nowStr,
      isFixedPair: nextMatch.isFixedPair,
    );

    final idx = _currentGames.indexWhere((g) => g.courtNumber == courtNumber);
    if (idx != -1) {
      _currentGames[idx] = enteredGame;
    } else {
      _currentGames.add(enteredGame);
      _currentGames.sort((a, b) => a.courtNumber.compareTo(b.courtNumber));
    }

    notifyListeners();
    return true;
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
      upcomingGames: upcomingGames,
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
