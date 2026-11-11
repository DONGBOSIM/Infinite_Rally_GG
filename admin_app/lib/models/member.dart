class Member {
  final String id;
  final String name;
  final String tier; // "A", "B", "C", "D", "초심"
  final String gender; // "M", "F"
  bool isPresent; // 당일 참석 여부
  int matchCountToday; // 오늘 경기 수

  Member({
    required this.id,
    required this.name,
    required this.tier,
    required this.gender,
    this.isPresent = false,
    this.matchCountToday = 0,
  });

  // 급수별 밸런스 점수 (매칭 밸런싱용)
  int get tierScore {
    switch (tier) {
      case 'A':
        return 4;
      case 'B':
        return 3;
      case 'C':
        return 2;
      case 'D':
        return 1;
      case '초심':
      default:
        return 0;
    }
  }

  Member copyWith({
    String? id,
    String? name,
    String? tier,
    String? gender,
    bool? isPresent,
    int? matchCountToday,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      tier: tier ?? this.tier,
      gender: gender ?? this.gender,
      isPresent: isPresent ?? this.isPresent,
      matchCountToday: matchCountToday ?? this.matchCountToday,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tier': tier,
      'gender': gender,
      'isPresent': isPresent,
      'matchCountToday': matchCountToday,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    return Member(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      tier: map['tier'] ?? '초심',
      gender: map['gender'] ?? 'M',
      isPresent: map['isPresent'] ?? false,
      matchCountToday: map['matchCountToday'] ?? 0,
    );
  }
}

