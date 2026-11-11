import 'game_match.dart';

class DailySession {
  final String sessionDate;
  String title;
  List<int> activeCourts;
  List<GameMatch> currentGames;
  List<Map<String, dynamic>> upcomingGames;
  String notice;
  DateTime updatedAt;

  DailySession({
    required this.sessionDate,
    required this.title,
    required this.activeCourts,
    required this.currentGames,
    required this.upcomingGames,
    required this.notice,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionDate': sessionDate,
      'title': title,
      'activeCourts': activeCourts,
      'notice': notice,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'currentGames': currentGames.map((m) => m.toMap()).toList(),
      'upcomingGames': upcomingGames,
    };
  }
}

