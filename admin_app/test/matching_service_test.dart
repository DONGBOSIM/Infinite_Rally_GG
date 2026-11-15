import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/models/member.dart';
import 'package:admin_app/services/matching_service.dart';

void main() {
  group('MatchingService 단위 테스트', () {
    test('참석 인원이 4명 미만일 때는 경기를 매칭하지 않는다', () {
      final members = [
        Member(id: '1', name: '김랠리', tier: 'A', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '2', name: '이민턴', tier: 'B', gender: 'F', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '3', name: '박스매시', tier: 'C', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 2,
      );

      expect(result.currentGames.isEmpty, true);
      expect(result.upcomingGames.isEmpty, true);
    });

    test('콕을 제출하지 않은 회원은 참석자이더라도 게임 매칭에서 제외된다 (규칙 3)', () {
      final members = [
        // 4명 중 1명만 콕 미제출
        Member(id: '1', name: '선수1', tier: 'A', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '2', name: '선수2', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '3', name: '선수3', tier: 'C', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '4', name: '선수4', tier: 'D', gender: 'M', isPresent: true, hasSubmittedShuttle: false), // 미제출
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      // 콕 제출자가 3명이므로 일반 매칭 불가
      expect(result.currentGames.isEmpty, true);
    });

    test('레슨 대기자(waiting) 및 레슨자(active)는 일반 게임 매칭에서 제외된다 (규칙 5)', () {
      final members = [
        Member(id: '1', name: '일반1', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '2', name: '일반2', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '3', name: '일반3', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        // 레슨 대기자 1명
        Member(id: '4', name: '레슨대기자', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, lessonStatus: 'waiting'),
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      // 일반 경기 가능 인원이 3명이므로 매칭되지 않음
      expect(result.currentGames.isEmpty, true);
    });

    test('4코트 레슨 모드 활성화 시 제 4코트에 레슨자 전용 코트가 생성된다 (규칙 4)', () {
      final members = [
        // 1~3코트용 일반 선수 12명 (모두 콕 제출 완료)
        ...List.generate(12, (i) => Member(
          id: 'player_$i',
          name: '선수$i',
          tier: 'C',
          gender: 'M',
          isPresent: true,
          hasSubmittedShuttle: true,
        )),
        // 레슨자 2명
        Member(id: 'l1', name: '레슨자1', tier: 'D', gender: 'F', isPresent: true, lessonStatus: 'active'),
        Member(id: 'l2', name: '레슨자2', tier: 'E', gender: 'M', isPresent: true, lessonStatus: 'active'),
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 4,
        isLessonCourtEnabled: true,
        lessonCoach: '김프로',
      );

      // 1, 2, 3코트는 일반 경기, 4코트는 레슨 코트
      expect(result.currentGames.length, 4);
      final court4 = result.currentGames.firstWhere((g) => g.courtNumber == 4);
      expect(court4.courtType, 'lesson');
      expect(court4.lessonCoach, '김프로');
      expect(court4.lessonStudents.length, 2);
      expect(court4.lessonStudents.any((s) => s.name == '레슨자1'), true);
      expect(court4.lessonStudents.any((s) => s.name == '레슨자2'), true);
    });

    test('고정 페어로 묶인 두 선수는 매칭 시 항상 같은 팀으로 배정된다 (고정 페어 보장)', () {
      final members = [
        // 1번과 2번이 상호 고정 페어
        Member(id: '1', name: '페어1', tier: 'A', gender: 'M', isPresent: true, hasSubmittedShuttle: true, fixedPartnerId: '2'),
        Member(id: '2', name: '페어2', tier: 'D', gender: 'F', isPresent: true, hasSubmittedShuttle: true, fixedPartnerId: '1'),
        Member(id: '3', name: '상대1', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
        Member(id: '4', name: '상대2', tier: 'C', gender: 'M', isPresent: true, hasSubmittedShuttle: true),
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      expect(result.currentGames.length, 1);
      final game = result.currentGames.first;
      expect(game.isFixedPair, true);

      // 페어1과 페어2가 한 팀(Team A 또는 Team B)에 함께 있어야 함
      final isBothInTeamA = game.teamA.any((m) => m.id == '1') && game.teamA.any((m) => m.id == '2');
      final isBothInTeamB = game.teamB.any((m) => m.id == '1') && game.teamB.any((m) => m.id == '2');
      expect(isBothInTeamA || isBothInTeamB, true);
    });

    test('출전 횟수가 적은 회원이 우선적으로 코트에 배정된다 (공평성 보장)', () {
      final members = [
        // 이미 2경기 치른 회원들
        Member(id: '1', name: '선수1', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 2),
        Member(id: '2', name: '선수2', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 2),
        Member(id: '3', name: '선수3', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 2),
        Member(id: '4', name: '선수4', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 2),

        // 아직 0경기 치른 회원들 (우선 선발 대상)
        Member(id: '5', name: '신규1', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 0),
        Member(id: '6', name: '신규2', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 0),
        Member(id: '7', name: '신규3', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 0),
        Member(id: '8', name: '신규4', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true, matchCountToday: 0),
      ];

      // 코트 1개(4명 선발) 설정
      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      expect(result.currentGames.length, 1);
      final assignedGame = result.currentGames.first;
      final assignedPlayerIds = [
        ...assignedGame.teamA.map((m) => m.id),
        ...assignedGame.teamB.map((m) => m.id),
      ];

      // 0경기 치른 신규 회원 4명이 모두 선발되어야 함
      expect(assignedPlayerIds.contains('5'), true);
      expect(assignedPlayerIds.contains('6'), true);
      expect(assignedPlayerIds.contains('7'), true);
      expect(assignedPlayerIds.contains('8'), true);
    });

    test('4명의 회원을 급수 차이가 최소화되도록 2:2 두 팀으로 균형 있게 페어링한다', () {
      final members = [
        Member(id: '1', name: 'A급선수', tier: 'A', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 4점
        Member(id: '2', name: 'B급선수', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 3점
        Member(id: '3', name: 'C급선수', tier: 'C', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 2점
        Member(id: '4', name: 'D급선수', tier: 'D', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 1점
      ];

      // 이상적인 밸런스: (A급 + D급 = 4+1 = 5점) vs (B급 + C급 = 3+2 = 5점) -> 점수 차이 0
      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      expect(result.currentGames.length, 1);
      final game = result.currentGames.first;
      expect(game.balanceDifference, 0); // 완벽한 밸런스 달성 확인
    });

    test('확장된 6단계 급수(S~E) 밸런싱이 올바르게 계산된다', () {
      final members = [
        Member(id: '1', name: 'S급선수', tier: 'S', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 5점
        Member(id: '2', name: 'B급선수', tier: 'B', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 3점
        Member(id: '3', name: 'C급선수', tier: 'C', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 2점
        Member(id: '4', name: 'E급선수', tier: 'E', gender: 'M', isPresent: true, hasSubmittedShuttle: true), // 0점
      ];

      // 이상적인 밸런스: (S + E = 5+0 = 5점) vs (B + C = 3+2 = 5점) -> 점수 차이 0
      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 1,
      );

      expect(result.currentGames.length, 1);
      final game = result.currentGames.first;
      expect(game.balanceDifference, 0);
    });
  });
}

