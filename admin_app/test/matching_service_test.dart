import 'package:flutter_test/flutter_test.dart';
import 'package:admin_app/models/member.dart';
import 'package:admin_app/services/matching_service.dart';

void main() {
  group('MatchingService 단위 테스트', () {
    test('참석 인원이 4명 미만일 때는 경기를 매칭하지 않는다', () {
      final members = [
        Member(id: '1', name: '김랠리', tier: 'A', gender: 'M', isPresent: true),
        Member(id: '2', name: '이민턴', tier: 'B', gender: 'F', isPresent: true),
        Member(id: '3', name: '박스매시', tier: 'C', gender: 'M', isPresent: true),
      ];

      final result = MatchingService.generateBalancedMatches(
        members: members,
        courtCount: 2,
      );

      expect(result.currentGames.isEmpty, true);
      expect(result.upcomingGames.isEmpty, true);
    });

    test('출전 횟수가 적은 회원이 우선적으로 코트에 배정된다 (공평성 보장)', () {
      final members = [
        // 이미 2경기 치른 회원들
        Member(id: '1', name: '선수1', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 2),
        Member(id: '2', name: '선수2', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 2),
        Member(id: '3', name: '선수3', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 2),
        Member(id: '4', name: '선수4', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 2),

        // 아직 0경기 치른 회원들 (우선 선발 대상)
        Member(id: '5', name: '신규1', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 0),
        Member(id: '6', name: '신규2', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 0),
        Member(id: '7', name: '신규3', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 0),
        Member(id: '8', name: '신규4', tier: 'B', gender: 'M', isPresent: true, matchCountToday: 0),
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
        Member(id: '1', name: 'A급선수', tier: 'A', gender: 'M', isPresent: true), // 4점
        Member(id: '2', name: 'B급선수', tier: 'B', gender: 'M', isPresent: true), // 3점
        Member(id: '3', name: 'C급선수', tier: 'C', gender: 'M', isPresent: true), // 2점
        Member(id: '4', name: 'D급선수', tier: 'D', gender: 'M', isPresent: true), // 1점
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
  });
}

