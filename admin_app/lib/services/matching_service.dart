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
    String lessonCoach = '코치님',
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
        lessonCoach: lessonCoach.isNotEmpty ? lessonCoach : '코치님',
        lessonStudents: activeLessonStudents,
        teamA: [],
        teamB: [],
        status: 'in_progress',
        startTime: nowStr,
      ));
    }

    // 4. 일반 복식 경기 매칭 (콕 제출자 4명 이상 필요)
    if (eligibleForGames.length >= 4 && regularCourtCount > 0) {
      // 공평 출전 기회 정렬: 오늘 경기 수 적은 순서 우선 -> 동일 시 랜덤 셔플
      final random = Random();
      eligibleForGames.shuffle(random);
      eligibleForGames.sort((a, b) => a.matchCountToday.compareTo(b.matchCountToday));

      // 현재 배정할 최대 인원 (일반 코트당 4명)
      final maxPlayersNeeded = regularCourtCount * 4;
      final int selectedCount = min(eligibleForGames.length - (eligibleForGames.length % 4), maxPlayersNeeded);

      final selectedForPlay = eligibleForGames.sublist(0, selectedCount);
      final waitingMembers = eligibleForGames.sublist(selectedCount);

      // 4명씩 묶어 코트별 밸런스 복식 팀 구성 (1코트부터 순차 배정)
      int actualCourts = selectedCount ~/ 4;
      for (int i = 0; i < actualCourts; i++) {
        final courtNumber = i + 1;
        final group = selectedForPlay.sublist(i * 4, (i + 1) * 4);
        final balancedTeams = _findBestDoublesPairing(group);

        currentGames.add(GameMatch(
          courtNumber: courtNumber,
          gameId: _uuid.v4().substring(0, 8),
          teamA: balancedTeams.$1,
          teamB: balancedTeams.$2,
          status: 'in_progress',
          startTime: nowStr,
        ));
      }

      // 남은 인원으로 대기 명단(upcomingGames) 구성 (일반 게임 코트에만 배정)
      int waitingOrder = 1;
      final targetCourts = actualCourts > 0 ? actualCourts : regularCourtCount;

      for (int i = 0; i + 3 < waitingMembers.length; i += 4) {
        final group = waitingMembers.sublist(i, i + 4);
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

  /// 4명의 회원을 급수 차이가 최소화되도록 2:2 두 팀으로 페어링
  static (List<Member>, List<Member>) _findBestDoublesPairing(List<Member> four) {
    if (four.length != 4) return ([four[0], four[1]], [four[2], four[3]]);

    final m1 = four[0];
    final m2 = four[1];
    final m3 = four[2];
    final m4 = four[3];

    // 3가지 가능한 복식 조합과 점수 차이
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

