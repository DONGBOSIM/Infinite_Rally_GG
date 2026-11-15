class Member {
  final String id;
  final String name;
  final String tier; // "S", "A", "B", "C", "D", "E" (하위 호환: "초심"은 "E"로 취급)
  final String gender; // "M", "F"
  bool isPresent; // 당일 참석 여부
  int matchCountToday; // 오늘 경기 수
  bool isGuest; // 게스트 여부
  bool hasSubmittedShuttle; // 콕 제출(출석 확정) 여부
  String lessonStatus; // "none" (일반), "waiting" (레슨 대기), "active" (레슨 진행중)
  String? fixedPartnerId; // 고정 페어(파트너) 회원 ID

  Member({
    required this.id,
    required this.name,
    required this.tier,
    required this.gender,
    this.isPresent = false,
    this.matchCountToday = 0,
    this.isGuest = false,
    this.hasSubmittedShuttle = false,
    this.lessonStatus = 'none',
    this.fixedPartnerId,
  });

  bool get isLesson => lessonStatus == 'active';
  set isLesson(bool val) {
    lessonStatus = val ? 'active' : 'none';
  }
  bool get isLessonWaiting => lessonStatus == 'waiting';
  bool get isLessonAny => lessonStatus != 'none';

  // 6단계 급수별 밸런스 점수 (매칭 밸런싱용: S=5, A=4, B=3, C=2, D=1, E=0)
  int get tierScore {
    switch (tier.toUpperCase()) {
      case 'S':
        return 5;
      case 'A':
        return 4;
      case 'B':
        return 3;
      case 'C':
        return 2;
      case 'D':
        return 1;
      case 'E':
      case '초심':
      default:
        return 0;
    }
  }

  // 화면 표시용 이름 (게스트일 경우 앞에 'G ' 표기)
  String get displayName {
    if (isGuest && !name.startsWith('G ')) {
      return 'G $name';
    }
    return name;
  }

  Member copyWith({
    String? id,
    String? name,
    String? tier,
    String? gender,
    bool? isPresent,
    int? matchCountToday,
    bool? isGuest,
    bool? hasSubmittedShuttle,
    String? lessonStatus,
    String? fixedPartnerId,
  }) {
    return Member(
      id: id ?? this.id,
      name: name ?? this.name,
      tier: tier ?? this.tier,
      gender: gender ?? this.gender,
      isPresent: isPresent ?? this.isPresent,
      matchCountToday: matchCountToday ?? this.matchCountToday,
      isGuest: isGuest ?? this.isGuest,
      hasSubmittedShuttle: hasSubmittedShuttle ?? this.hasSubmittedShuttle,
      lessonStatus: lessonStatus ?? this.lessonStatus,
      fixedPartnerId: fixedPartnerId ?? this.fixedPartnerId,
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
      'isGuest': isGuest,
      'hasSubmittedShuttle': hasSubmittedShuttle,
      'lessonStatus': lessonStatus,
      'isLesson': isLesson, // 웹 뷰어 등 하위 호환용
      'fixedPartnerId': fixedPartnerId,
    };
  }

  factory Member.fromMap(Map<String, dynamic> map) {
    String parseLessonStatus() {
      if (map['lessonStatus'] != null) {
        return map['lessonStatus'];
      }
      if (map['isLesson'] == true) {
        return 'active';
      }
      return 'none';
    }

    return Member(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      tier: map['tier'] ?? 'E',
      gender: map['gender'] ?? 'M',
      isPresent: map['isPresent'] ?? false,
      matchCountToday: map['matchCountToday'] ?? 0,
      isGuest: map['isGuest'] ?? false,
      hasSubmittedShuttle: map['hasSubmittedShuttle'] ?? false,
      lessonStatus: parseLessonStatus(),
      fixedPartnerId: map['fixedPartnerId'],
    );
  }
}

