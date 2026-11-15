import 'game_match.dart';
import 'member.dart';

class DailySession {
  final String sessionDate;
  String title;
  List<int> activeCourts;
  List<GameMatch> currentGames;
  List<Map<String, dynamic>> upcomingGames;
  String notice;
  DateTime updatedAt;
  bool isLessonCourtEnabled; // 4코트 레슨 모드 활성화 여부
  String lessonCoach; // 레슨 코치 이름
  List<Map<String, dynamic>> lessonQueue; // 레슨 대기 명단
  List<Member> members; // 다중 관리자 동기화용 회원 및 출석 상태

  DailySession({
    required this.sessionDate,
    required this.title,
    required this.activeCourts,
    required this.currentGames,
    required this.upcomingGames,
    required this.notice,
    required this.updatedAt,
    this.isLessonCourtEnabled = true,
    this.lessonCoach = '코치님',
    this.lessonQueue = const [],
    this.members = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionDate': sessionDate,
      'title': title,
      'activeCourts': activeCourts,
      'notice': notice,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'isLessonCourtEnabled': isLessonCourtEnabled,
      'lessonCoach': lessonCoach,
      'lessonQueue': lessonQueue,
      'currentGames': currentGames.map((m) => m.toMap()).toList(),
      'upcomingGames': upcomingGames,
      'members': members.map((m) => m.toMap()).toList(),
    };
  }

  factory DailySession.fromMap(Map<String, dynamic> map) {
    List<GameMatch> parseGames(dynamic gamesData) {
      if (gamesData is List) {
        return gamesData.map((g) => GameMatch.fromMap(Map<String, dynamic>.from(g))).toList();
      }
      return [];
    }

    List<Map<String, dynamic>> parseUpcoming(dynamic upcomingData) {
      if (upcomingData is List) {
        return upcomingData.map((u) => Map<String, dynamic>.from(u)).toList();
      }
      return [];
    }

    List<Map<String, dynamic>> parseLessonQueue(dynamic queueData) {
      if (queueData is List) {
        return queueData.map((q) => Map<String, dynamic>.from(q)).toList();
      }
      return [];
    }

    List<Member> parseMembers(dynamic membersData) {
      if (membersData is List) {
        return membersData.map((m) => Member.fromMap(Map<String, dynamic>.from(m))).toList();
      }
      return [];
    }

    List<int> parseCourts(dynamic courtsData) {
      if (courtsData is List) {
        return courtsData.map((c) => int.tryParse(c.toString()) ?? 1).toList();
      }
      return [1, 2, 3, 4];
    }

    DateTime parseUpdated(dynamic updated) {
      if (updated is String) {
        return DateTime.tryParse(updated) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return DailySession(
      sessionDate: map['sessionDate'] ?? '',
      title: map['title'] ?? '',
      activeCourts: parseCourts(map['activeCourts']),
      currentGames: parseGames(map['currentGames']),
      upcomingGames: parseUpcoming(map['upcomingGames']),
      notice: map['notice'] ?? '',
      updatedAt: parseUpdated(map['updatedAt']),
      isLessonCourtEnabled: map['isLessonCourtEnabled'] ?? true,
      lessonCoach: map['lessonCoach'] ?? '코치님',
      lessonQueue: parseLessonQueue(map['lessonQueue']),
      members: parseMembers(map['members']),
    );
  }
}

