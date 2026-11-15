import 'member.dart';

class GameMatch {
  final int courtNumber;
  final String gameId;
  final List<Member> teamA;
  final List<Member> teamB;
  String status; // "in_progress", "finished", "waiting"
  String startTime;
  String courtType; // "game" 또는 "lesson"
  String lessonCoach; // 레슨 코치명 (courtType이 lesson일 때)
  List<Member> lessonStudents; // 레슨 참여 인원 목록
  bool isFixedPair; // 고정 페어가 포함된 경기인지 여부

  GameMatch({
    required this.courtNumber,
    required this.gameId,
    required this.teamA,
    required this.teamB,
    this.status = 'in_progress',
    required this.startTime,
    this.courtType = 'game',
    this.lessonCoach = '',
    this.lessonStudents = const [],
    this.isFixedPair = false,
  });

  bool get isLesson => courtType == 'lesson';

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
      'courtType': courtType,
      'lessonCoach': lessonCoach,
      'lessonStudents': lessonStudents.map((s) => s.toMap()).toList(),
      'isFixedPair': isFixedPair,
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

  factory GameMatch.fromMap(Map<String, dynamic> map) {
    List<Member> parseTeam(dynamic teamData) {
      if (teamData == null) return [];
      final List<Member> list = [];
      if (teamData is Map<String, dynamic>) {
        if (teamData['player1'] != null && (teamData['player1']['name'] ?? '').toString().isNotEmpty) {
          final p1 = teamData['player1'];
          list.add(Member(
            id: p1['id'] ?? '',
            name: p1['name'] ?? '',
            tier: p1['tier'] ?? 'E',
            gender: p1['gender'] ?? 'M',
          ));
        }
        if (teamData['player2'] != null && (teamData['player2']['name'] ?? '').toString().isNotEmpty) {
          final p2 = teamData['player2'];
          list.add(Member(
            id: p2['id'] ?? '',
            name: p2['name'] ?? '',
            tier: p2['tier'] ?? 'E',
            gender: p2['gender'] ?? 'M',
          ));
        }
      }
      return list;
    }

    List<Member> parseStudents(dynamic studentsData) {
      if (studentsData is List) {
        return studentsData.map((s) => Member.fromMap(Map<String, dynamic>.from(s))).toList();
      }
      return [];
    }

    return GameMatch(
      courtNumber: map['courtNumber'] ?? 1,
      gameId: map['gameId'] ?? '',
      teamA: parseTeam(map['teamA']),
      teamB: parseTeam(map['teamB']),
      status: map['status'] ?? 'in_progress',
      startTime: map['startTime'] ?? '',
      courtType: map['courtType'] ?? 'game',
      lessonCoach: map['lessonCoach'] ?? '',
      lessonStudents: parseStudents(map['lessonStudents']),
      isFixedPair: map['isFixedPair'] ?? false,
    );
  }
}

