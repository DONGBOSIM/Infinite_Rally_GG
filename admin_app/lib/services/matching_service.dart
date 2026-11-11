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

  /// 참석자 명단과 사용 코트 수를 기반으로 공평 복식 매칭 생성
  static MatchingResult generateBalancedMatches({
    required List<Member> members,
    required int courtCount,
  }) {
    // 1. 당일 참석 회원 필터링
    final presentMembers = members.where((m) => m.isPresent).toList();

    if (presentMembers.length < 4) {
      return MatchingResult(currentGames: [], upcomingGames: []);
    }

    // 2. 공평 출전 기회 정렬:
    //    오늘 참여 경기 수가 적은 순서 우선 -> 같은 경기 수 내에서는 랜덤 셔플
    final random = Random();
    presentMembers.shuffle(random);
    presentMembers.sort((a, b) => a.matchCountToday.compareTo(b.matchCountToday));

    // 3. 현재 코트에 배정할 최대 인원 (코트당 4명)
    final maxPlayersNeeded = courtCount * 4;
    final int selectedCount = min(presentMembers.length - (presentMembers.length % 4), maxPlayersNeeded);

    final selectedForPlay = presentMembers.sublist(0, selectedCount);
    final waitingMembers = presentMembers.sublist(selectedCount);

    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    final List<GameMatch> currentGames = [];

    // 4. 선발된 인원을 4명씩 묶어 코트별 밸런스 복식 팀 구성
    int actualCourts = selectedCount ~/ 4;
    for (int i = 0; i < actualCourts; i++) {
      final courtNumber = i + 1;
      final group = selectedForPlay.sublist(i * 4, (i + 1) * 4);

      // 4명 중 급수 밸런스(점수 차이 최소)가 가장 좋은 팀 조합 찾기
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

    // 5. 남은 인원으로 대기 명단(upcomingGames) 구성
    final List<Map<String, dynamic>> upcomingGames = [];
    int waitingOrder = 1;

    for (int i = 0; i + 3 < waitingMembers.length; i += 4) {
      final group = waitingMembers.sublist(i, i + 4);
      final balancedTeams = _findBestDoublesPairing(group);

      upcomingGames.add({
        'order': waitingOrder,
        'designatedCourt': ((waitingOrder - 1) % actualCourts) + 1,
        'teamA': balancedTeams.$1.map((m) => '${m.name} (${m.tier})').toList(),
        'teamB': balancedTeams.$2.map((m) => '${m.name} (${m.tier})').toList(),
      });
      waitingOrder++;
    }

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

