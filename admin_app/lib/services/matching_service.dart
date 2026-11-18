import 'dart:math';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/member.dart';
import '../models/game_match.dart';

class MatchingResult {
  final List<GameMatch> currentGames;
  final List<Map<String, dynamic>> upcomingGames;

  MatchingResult({
    required this.currentGames,
    required this.upcomingGames,
  });
}

class MatchingService {
  static const _uuid = Uuid();

  /// 콕 제출 출석자 명단과 사용 코트 수, 레슨 코트 옵션을 기반으로 공평 복식 매칭 생성
  static MatchingResult generateBalancedMatches({
    required List<Member> members,
    required int courtCount,
    bool isLessonCourtEnabled = false,
    String lessonCoach = '무한랠리도우미',
  }) {
    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    final List<GameMatch> currentGames = [];
    final List<Map<String, dynamic>> upcomingGames = [];

    // 1. 4코트 레슨 모드 여부 확인 (4코트 이상이고 활성화된 경우 제 4코트는 레슨 전용)
    final bool useLessonCourt = isLessonCourtEnabled && courtCount >= 4;
    final int regularCourtCount = useLessonCourt ? courtCount - 1 : courtCount;

    // 2. 당일 참석 & 콕 제출(출석 확정) & 일반 경기 대상(레슨 제외) 회원 필터링
    final eligibleForGames = members.where((m) =>
        m.isPresent && m.hasSubmittedShuttle && m.lessonStatus == 'none').toList();

    // 3. 레슨 코트 (제 4코트) 생성 (레슨 모드 활성화 시)
    if (useLessonCourt) {
      final activeLessonStudents = members.where((m) => m.isPresent && m.lessonStatus == 'active').toList();
      currentGames.add(GameMatch(
        courtNumber: 4,
        gameId: 'lesson_${_uuid.v4().substring(0, 8)}',
        courtType: 'lesson',
        lessonCoach: (lessonCoach.isNotEmpty && lessonCoach != '코치님') ? lessonCoach : '무한랠리도우미',
        lessonStudents: activeLessonStudents,
        teamA: [],
        teamB: [],
        status: 'in_progress',
        startTime: nowStr,
      ));
    }

    // 4. 일반 복식 경기 매칭 (콕 제출자 4명 이상 필요)
    if (eligibleForGames.length >= 4 && regularCourtCount > 0) {
      // 고정 페어(파트너) 보장 및 공평 출전 기회를 반영한 4인 그룹 편성
      final groups = _assembleFourPlayerGroups(eligibleForGames);

      // 코트별 경기 배정 (1코트부터 순차 배정)
      final int actualCourts = min(groups.length, regularCourtCount);
      for (int i = 0; i < actualCourts; i++) {
        final courtNumber = i + 1;
        final group = groups[i];
        final balancedTeams = _findBestDoublesPairing(group);
        final hasFixedPair = group.any((m) =>
            m.fixedPartnerId != null && group.any((other) => other.id == m.fixedPartnerId && other.id != m.id));

        currentGames.add(GameMatch(
          courtNumber: courtNumber,
          gameId: _uuid.v4().substring(0, 8),
          teamA: balancedTeams.$1,
          teamB: balancedTeams.$2,
          status: 'in_progress',
          startTime: nowStr,
          isFixedPair: hasFixedPair,
        ));
      }

      // 남은 그룹으로 대기 명단(upcomingGames) 구성 (일반 게임 코트에만 배정)
      int waitingOrder = 1;
      final targetCourts = actualCourts > 0 ? actualCourts : regularCourtCount;

      for (int i = actualCourts; i < groups.length; i++) {
        final group = groups[i];
        final balancedTeams = _findBestDoublesPairing(group);

        upcomingGames.add({
          'order': waitingOrder,
          'designatedCourt': ((waitingOrder - 1) % targetCourts) + 1,
          'teamA': balancedTeams.$1.map((m) => '${m.name} (${m.tier})').toList(),
          'teamB': balancedTeams.$2.map((m) => '${m.name} (${m.tier})').toList(),
        });
        waitingOrder++;
      }
    }

    // 코트 번호 순서대로 정렬 (제 1코트, 2코트, 3코트, 4코트 순서)
    currentGames.sort((a, b) => a.courtNumber.compareTo(b.courtNumber));

    return MatchingResult(
      currentGames: currentGames,
      upcomingGames: upcomingGames,
    );
  }

  /// 대기 중인 가용 회원들을 대상으로 공평 복식 매칭들을 생성하여 반환 (대기열 전용 생성 함수)
  static List<GameMatch> createBalancedMatchesForQueue(List<Member> availableMembers) {
    if (availableMembers.length < 4) return [];
    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    final groups = _assembleFourPlayerGroups(availableMembers);
    final List<GameMatch> matches = [];

    for (final group in groups) {
      final balancedTeams = _findBestDoublesPairing(group);
      final hasFixedPair = group.any((m) =>
          m.fixedPartnerId != null &&
          group.any((other) => other.id == m.fixedPartnerId && other.id != m.id));

      matches.add(GameMatch(
        courtNumber: 0, // 대기열이므로 코트 미배정
        gameId: _uuid.v4().substring(0, 8),
        teamA: balancedTeams.$1,
        teamB: balancedTeams.$2,
        status: 'waiting',
        startTime: nowStr,
        isFixedPair: hasFixedPair,
      ));
    }

    return matches;
  }

  /// 고정 페어(파트너)를 묶고 경기 수 기반으로 4인 매칭 그룹 구성
  static List<List<Member>> _assembleFourPlayerGroups(List<Member> eligible) {
    final random = Random();
    final Set<String> pairedIds = {};
    final List<List<Member>> pairs = [];
    final List<Member> solos = [];

    // 1. 유효한 고정 페어 식별 (둘 다 출석 및 경기 대상인 경우)
    for (final m in eligible) {
      if (pairedIds.contains(m.id)) continue;
      if (m.fixedPartnerId != null && m.fixedPartnerId!.isNotEmpty) {
        final partner = eligible.firstWhere(
          (other) => other.id == m.fixedPartnerId && other.id != m.id,
          orElse: () => Member(id: '', name: '', tier: 'E', gender: 'M'),
        );
        if (partner.id.isNotEmpty && !pairedIds.contains(partner.id)) {
          pairedIds.add(m.id);
          pairedIds.add(partner.id);
          pairs.add([m, partner]);
          continue;
        }
      }
      solos.add(m);
    }

    // 셔플 및 경기 수 오름차순 정렬 (공평 출전 기회 보장)
    pairs.shuffle(random);
    pairs.sort((a, b) {
      final avgA = (a[0].matchCountToday + a[1].matchCountToday) / 2.0;
      final avgB = (b[0].matchCountToday + b[1].matchCountToday) / 2.0;
      return avgA.compareTo(avgB);
    });

    solos.shuffle(random);
    solos.sort((a, b) => a.matchCountToday.compareTo(b.matchCountToday));

    final List<List<Member>> groups = [];

    // 2. 4인 그룹 구성
    while (true) {
      final hasPair = pairs.isNotEmpty;
      final hasAtLeastTwoSolos = solos.length >= 2;
      final hasAtLeastFourSolos = solos.length >= 4;
      final hasAtLeastTwoPairs = pairs.length >= 2;

      if (!hasPair && !hasAtLeastFourSolos) {
        break;
      }

      final pairPriority = hasPair
          ? (pairs.first[0].matchCountToday + pairs.first[1].matchCountToday) / 2.0
          : double.infinity;
      final soloPriority = hasAtLeastFourSolos
          ? solos.take(4).fold<int>(0, (s, m) => s + m.matchCountToday) / 4.0
          : (hasAtLeastTwoSolos ? (solos[0].matchCountToday + solos[1].matchCountToday) / 2.0 : double.infinity);

      if (hasPair && (pairPriority <= soloPriority || !hasAtLeastFourSolos)) {
        final p1 = pairs.removeAt(0);
        if (hasAtLeastTwoPairs && pairs.isNotEmpty && (pairs.first[0].matchCountToday + pairs.first[1].matchCountToday) / 2.0 <= soloPriority) {
          final p2 = pairs.removeAt(0);
          groups.add([...p1, ...p2]);
        } else if (solos.length >= 2) {
          final s1 = solos.removeAt(0);
          final s2 = solos.removeAt(0);
          groups.add([...p1, s1, s2]);
        } else if (pairs.isNotEmpty) {
          final p2 = pairs.removeAt(0);
          groups.add([...p1, ...p2]);
        } else {
          pairs.insert(0, p1);
          break;
        }
      } else if (hasAtLeastFourSolos) {
        final s1 = solos.removeAt(0);
        final s2 = solos.removeAt(0);
        final s3 = solos.removeAt(0);
        final s4 = solos.removeAt(0);
        groups.add([s1, s2, s3, s4]);
      } else if (hasPair && solos.length >= 2) {
        final p1 = pairs.removeAt(0);
        final s1 = solos.removeAt(0);
        final s2 = solos.removeAt(0);
        groups.add([...p1, s1, s2]);
      } else {
        break;
      }
    }

    return groups;
  }

  /// 4명의 회원을 2:2 두 팀으로 페어링 (고정 페어가 있으면 반드시 한 팀으로 묶음)
  static (List<Member>, List<Member>) _findBestDoublesPairing(List<Member> four) {
    if (four.length != 4) return ([four[0], four[1]], [four[2], four[3]]);

    // 1. 고정 페어(파트너) 확인 -> 고정 파트너는 반드시 같은 팀
    for (int i = 0; i < four.length; i++) {
      for (int j = i + 1; j < four.length; j++) {
        final a = four[i];
        final b = four[j];
        if (a.fixedPartnerId != null && a.fixedPartnerId == b.id) {
          final others = four.where((m) => m.id != a.id && m.id != b.id).toList();
          return ([a, b], others);
        }
      }
    }

    // 2. 고정 페어가 없는 경우: 3가지 조합 중 급수 점수 차이 최소인 조합 선택
    final m1 = four[0];
    final m2 = four[1];
    final m3 = four[2];
    final m4 = four[3];

    final combo1Diff = ((m1.tierScore + m2.tierScore) - (m3.tierScore + m4.tierScore)).abs();
    final combo2Diff = ((m1.tierScore + m3.tierScore) - (m2.tierScore + m4.tierScore)).abs();
    final combo3Diff = ((m1.tierScore + m4.tierScore) - (m2.tierScore + m3.tierScore)).abs();

    if (combo1Diff <= combo2Diff && combo1Diff <= combo3Diff) {
      return ([m1, m2], [m3, m4]);
    } else if (combo2Diff <= combo1Diff && combo2Diff <= combo3Diff) {
      return ([m1, m3], [m2, m4]);
    } else {
      return ([m1, m4], [m2, m3]);
    }
  }
}

