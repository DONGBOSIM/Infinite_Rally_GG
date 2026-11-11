import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/daily_session.dart';
import '../models/member.dart';

class FirestoreService {
  FirebaseFirestore? _firestore;

  bool get isFirebaseAvailable {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  FirebaseFirestore? get firestore {
    if (!isFirebaseAvailable) return null;
    try {
      _firestore ??= FirebaseFirestore.instance;
      return _firestore;
    } catch (_) {
      return null;
    }
  }

  /// 당일 세션 및 매칭 정보를 Firestore 'daily_sessions/{sessionDate}'에 업로드
  Future<bool> uploadDailySession(DailySession session) async {
    final db = firestore;
    if (db == null) {
      // ignore: avoid_print
      print('Firebase가 아직 설정되지 않아 로컬 모드로 작동 중입니다 (google-services.json 필요).');
      return false;
    }

    try {
      await db
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
    final db = firestore;
    if (db == null) return false;

    try {
      final batch = db.batch();
      final usersCol = db.collection('users');

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
    final db = firestore;
    if (db == null) return [];

    try {
      final snapshot = await db.collection('users').get();
      return snapshot.docs.map((doc) => Member.fromMap(doc.data())).toList();
    } catch (e) {
      // ignore: avoid_print
      print('Firestore fetchMembers Error: $e');
      return [];
    }
  }
}
