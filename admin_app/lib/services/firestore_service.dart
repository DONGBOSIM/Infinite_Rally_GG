import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/daily_session.dart';
import '../models/member.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 당일 세션 및 매칭 정보를 Firestore 'daily_sessions/{sessionDate}'에 업로드
  Future<bool> uploadDailySession(DailySession session) async {
    try {
      await _firestore
          .collection('daily_sessions')
          .doc(session.sessionDate)
          .set(session.toMap(), SetOptions(merge: true));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('Firestore uploadDailySession Error: $e');
      return false;
    }
  }

  /// 전체 회원 목록을 Firestore 'users' 컬렉션에 일괄 저장
  Future<bool> saveMembers(List<Member> members) async {
    try {
      final batch = _firestore.batch();
      final usersCol = _firestore.collection('users');

      for (final member in members) {
        final docRef = usersCol.doc(member.id);
        batch.set(docRef, member.toMap(), SetOptions(merge: true));
      }

      await batch.commit();
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('Firestore saveMembers Error: $e');
      return false;
    }
  }

  /// Firestore 'users' 컬렉션에서 회원 목록 로드
  Future<List<Member>> fetchMembers() async {
    try {
      final snapshot = await _firestore.collection('users').get();
      return snapshot.docs.map((doc) => Member.fromMap(doc.data())).toList();
    } catch (e) {
      // ignore: avoid_print
      print('Firestore fetchMembers Error: $e');
      return [];
    }
  }
}

