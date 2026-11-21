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
    Map<String, Set<String>>? recentPartnerMap,
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
      // 고정 페어(파트너)·공평 출전 기회·성별 균형·직전 파트너 회피를 반영한 4인 그룹 편성
      final groups = _assembleFourPlayerGroups(
        eligibleForGames,
        recentPartnerMap: recentPartnerMap,
      );

      // 코트별 경기 배정 (1코트부터 순차 배정)
      final int actualCourts = min(groups.length, regularCourtCount);
      for (int i = 0; i < actualCourts; i++) {
        final courtNumber = i + 1;
        final group = groups[i];
        final balancedTeams = _findBestDoublesPairing(
          group,
          recentPartnerMap: recentPartnerMap,
        );
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
        final balancedTeams = _findBestDoublesPairing(
          group,
          recentPartnerMap: recentPartnerMap,
        );

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
  static List<GameMatch> createBalancedMatchesForQueue(
    List<Member> availableMembers, {
    Map<String, Set<String>>? recentPartnerMap,
  }) {
    if (availableMembers.length < 4) return [];
    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    final groups = _assembleFourPlayerGroups(
      availableMembers,
      recentPartnerMap: recentPartnerMap,
    );
    final List<GameMatch> matches = [];

    for (final group in groups) {
      final balancedTeams = _findBestDoublesPairing(
        group,
        recentPartnerMap: recentPartnerMap,
      );
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

  static bool _isRecentPartner(
    Member a,
    Member b,
    Map<String, Set<String>>? recentPartnerMap,
  ) {
    if (recentPartnerMap == null) return false;
    final partnersA = recentPartnerMap[a.id];
    if (partnersA != null && partnersA.contains(b.id)) return true;
    final partnersB = recentPartnerMap[b.id];
    if (partnersB != null && partnersB.contains(a.id)) return true;
    return false;
  }

  /// 2:2 팀 분할 비용 평가 (낮을수록 이상적)
  /// - 급수 점수 차 * 10
  /// - 2남 2여(혼복 가능)일 때 남복 vs 여복(남2 vs 여2) 분할 시 +18 페널티 (혼복 우선)
  /// - 직전 경기 동일 파트너 연속 배정 시 팀당 +25 페널티
  static int _evaluateSplitCost(
    List<Member> teamA,
    List<Member> teamB,
    Map<String, Set<String>>? recentPartnerMap,
  ) {
    final scoreA = teamA.fold<int>(0, (s, m) => s + m.tierScore);
    final scoreB = teamB.fold<int>(0, (s, m) => s + m.tierScore);
    int cost = (scoreA - scoreB).abs() * 10;

    if (teamA.length == 2 && teamB.length == 2) {
      final aMales = teamA.where((m) => m.gender == 'M').length;
      final bMales = teamB.where((m) => m.gender == 'M').length;
      if ((aMales == 2 && bMales == 0) || (aMales == 0 && bMales == 2)) {
        cost += 18;
      }
      if (_isRecentPartner(teamA[0], teamA[1], recentPartnerMap)) {
        cost += 25;
      }
      if (_isRecentPartner(teamB[0], teamB[1], recentPartnerMap)) {
        cost += 25;
      }
    }
    return cost;
  }

  /// 4인 그룹 품질 평가 (출전 횟수 공평성 > 3:1 성별 불균형 회피 > 2:2 분할 비용)
  static int _evaluateGroupCost(
    List<Member> four,
    int minMatchSum,
    Map<String, Set<String>>? recentPartnerMap,
  ) {
    final matchSum = four.fold<int>(0, (s, m) => s + m.matchCountToday);
    final matchPenalty = (matchSum - minMatchSum).abs() * 1000;
    final maleCount = four.where((m) => m.gender == 'M').length;
    final genderPenalty = (maleCount == 1 || maleCount == 3) ? 50 : 0;
    final pairing = _bestPairingWithCost(four, recentPartnerMap: recentPartnerMap);
    return matchPenalty + genderPenalty + pairing.$3;
  }

  /// 고정 페어(파트너)를 묶고 경기 수·성별·직전 파트너 이력을 반영해 4인 매칭 그룹 구성
  static List<List<Member>> _assembleFourPlayerGroups(
    List<Member> eligible, {
    Map<String, Set<String>>? recentPartnerMap,
  }) {
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

    List<Member> pickBestTwoSolos(List<Member> fixedPair) {
      final cutoff = solos[1].matchCountToday;
      int windowEnd = 2;
      while (windowEnd < solos.length && windowEnd < 10 && solos[windowEnd].matchCountToday <= cutoff) {
        windowEnd++;
      }

      if (windowEnd == 2) {
        final s1 = solos.removeAt(0);
        final s2 = solos.removeAt(0);
        return [...fixedPair, s1, s2];
      }

      final minSum = fixedPair[0].matchCountToday +
          fixedPair[1].matchCountToday +
          solos[0].matchCountToday +
          solos[1].matchCountToday;

      int bestI = 0;
      int bestJ = 1;
      int bestCost = 1 << 30;

      for (int i = 0; i < windowEnd; i++) {
        for (int j = i + 1; j < windowEnd; j++) {
          final group = [...fixedPair, solos[i], solos[j]];
          final cost = _evaluateGroupCost(group, minSum, recentPartnerMap);
          if (cost < bestCost) {
            bestCost = cost;
            bestI = i;
            bestJ = j;
          }
        }
      }

      final s2 = solos.removeAt(bestJ);
      final s1 = solos.removeAt(bestI);
      return [...fixedPair, s1, s2];
    }

    List<Member> pickBestFourSolos() {
      final cutoff = solos[3].matchCountToday;
      int windowEnd = 4;
      while (windowEnd < solos.length && windowEnd < 10 && solos[windowEnd].matchCountToday <= cutoff) {
        windowEnd++;
      }

      if (windowEnd == 4) {
        final s1 = solos.removeAt(0);
        final s2 = solos.removeAt(0);
        final s3 = solos.removeAt(0);
        final s4 = solos.removeAt(0);
        return [s1, s2, s3, s4];
      }

      final anchor = solos[0];
      final minSum = solos[0].matchCountToday +
          solos[1].matchCountToday +
          solos[2].matchCountToday +
          solos[3].matchCountToday;

      int bestI = 1;
      int bestJ = 2;
      int bestK = 3;
      int bestCost = 1 << 30;

      for (int i = 1; i < windowEnd; i++) {
        for (int j = i + 1; j < windowEnd; j++) {
          for (int k = j + 1; k < windowEnd; k++) {
            final group = [anchor, solos[i], solos[j], solos[k]];
            final cost = _evaluateGroupCost(group, minSum, recentPartnerMap);
            if (cost < bestCost) {
              bestCost = cost;
              bestI = i;
              bestJ = j;
              bestK = k;
            }
          }
        }
      }

      final s4 = solos.removeAt(bestK);
      final s3 = solos.removeAt(bestJ);
      final s2 = solos.removeAt(bestI);
      final s1 = solos.removeAt(0);
      return [s1, s2, s3, s4];
    }

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
          groups.add(pickBestTwoSolos(p1));
        } else if (pairs.isNotEmpty) {
          final p2 = pairs.removeAt(0);
          groups.add([...p1, ...p2]);
        } else {
          pairs.insert(0, p1);
          break;
        }
      } else if (hasAtLeastFourSolos) {
        groups.add(pickBestFourSolos());
      } else if (hasPair && solos.length >= 2) {
        final p1 = pairs.removeAt(0);
        groups.add(pickBestTwoSolos(p1));
      } else {
        break;
      }
    }

    return groups;
  }

  /// 4명의 회원을 2:2 두 팀으로 페어링 + 비용 계산 반환
  static (List<Member>, List<Member>, int) _bestPairingWithCost(
    List<Member> four, {
    Map<String, Set<String>>? recentPartnerMap,
  }) {
    if (four.length != 4) {
      return ([four[0], four[1]], [four[2], four[3]], 0);
    }

    // 1. 고정 페어(파트너) 확인 -> 고정 파트너는 반드시 같은 팀
    for (int i = 0; i < four.length; i++) {
      for (int j = i + 1; j < four.length; j++) {
        final a = four[i];
        final b = four[j];
        if (a.fixedPartnerId != null && a.fixedPartnerId == b.id) {
          final teamA = [a, b];
          final teamB = four.where((m) => m.id != a.id && m.id != b.id).toList();
          return (teamA, teamB, _evaluateSplitCost(teamA, teamB, recentPartnerMap));
        }
      }
    }

    // 2. 고정 페어가 없는 경우: 3가지 조합 중 비용(급수 차 + 성별 불균형 + 직전 파트너 중복) 최소인 조합 선택
    final m1 = four[0];
    final m2 = four[1];
    final m3 = four[2];
    final m4 = four[3];

    final combos = [
      ([m1, m2], [m3, m4]),
      ([m1, m3], [m2, m4]),
      ([m1, m4], [m2, m3]),
    ];

    var bestPair = combos[0];
    var bestCost = _evaluateSplitCost(bestPair.$1, bestPair.$2, recentPartnerMap);

    for (int c = 1; c < combos.length; c++) {
      final cand = combos[c];
      final cost = _evaluateSplitCost(cand.$1, cand.$2, recentPartnerMap);
      if (cost < bestCost) {
        bestCost = cost;
        bestPair = cand;
      }
    }

    return (bestPair.$1, bestPair.$2, bestCost);
  }

  /// 4명의 회원을 2:2 두 팀으로 페어링 (고정 페어가 있으면 반드시 한 팀으로 묶음)
  static (List<Member>, List<Member>) _findBestDoublesPairing(
    List<Member> four, {
    Map<String, Set<String>>? recentPartnerMap,
  }) {
    final res = _bestPairingWithCost(four, recentPartnerMap: recentPartnerMap);
    return (res.$1, res.$2);
  }
}

