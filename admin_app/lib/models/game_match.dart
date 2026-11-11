import 'member.dart';

class GameMatch {
  final int courtNumber;
  final String gameId;
  final List<Member> teamA;
  final List<Member> teamB;
  String status; // "in_progress", "finished", "waiting"
  String startTime;

  GameMatch({
    required this.courtNumber,
    required this.gameId,
    required this.teamA,
    required this.teamB,
    this.status = 'in_progress',
    required this.startTime,
  });

  // 두 팀의 티어 점수 차이 (밸런스 평가용)
  int get balanceDifference {
    final scoreA = teamA.fold<int>(0, (sum, m) => sum + m.tierScore);
    final scoreB = teamB.fold<int>(0, (sum, m) => sum + m.tierScore);
    return (scoreA - scoreB).abs();
  }

  Map<String, dynamic> toMap() {
    return {
      'courtNumber': courtNumber,
      'gameId': gameId,
      'status': status,
      'startTime': startTime,
      'teamA': {
        'player1': {
          'id': teamA.isNotEmpty ? teamA[0].id : '',
          'name': teamA.isNotEmpty ? teamA[0].name : '',
          'tier': teamA.isNotEmpty ? teamA[0].tier : '',
        },
        'player2': {
          'id': teamA.length > 1 ? teamA[1].id : '',
          'name': teamA.length > 1 ? teamA[1].name : '',
          'tier': teamA.length > 1 ? teamA[1].tier : '',
        },
      },
      'teamB': {
        'player1': {
          'id': teamB.isNotEmpty ? teamB[0].id : '',
          'name': teamB.isNotEmpty ? teamB[0].name : '',
          'tier': teamB.isNotEmpty ? teamB[0].tier : '',
        },
        'player2': {
          'id': teamB.length > 1 ? teamB[1].id : '',
          'name': teamB.length > 1 ? teamB[1].name : '',
          'tier': teamB.length > 1 ? teamB[1].tier : '',
        },
      },
    };
  }
}

