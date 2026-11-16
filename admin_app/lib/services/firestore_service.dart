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

  /// 당일 세션 데이터 실시간 구독 (다중 관리자 실시간 동기화용)
  Stream<DailySession?> listenDailySession(String sessionDate) {
    final db = firestore;
    if (db == null) return const Stream.empty();

    return db
        .collection('daily_sessions')
        .doc(sessionDate)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return DailySession.fromMap(snapshot.data()!);
      }
      return null;
    });
  }

  /// 당일 세션 데이터 1회 가져오기
  Future<DailySession?> fetchDailySession(String sessionDate) async {
    final db = firestore;
    if (db == null) return null;

    try {
      final doc = await db.collection('daily_sessions').doc(sessionDate).get();
      if (doc.exists && doc.data() != null) {
        return DailySession.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Firestore fetchDailySession Error: $e');
      return null;
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

  /// 전체 정회원 명부(Master Members)를 단일 문서('club_metadata/master_members')에 영구 저장 (0원 무과금 최적화: 쓰기 1회)
  Future<bool> saveMasterMembers(List<Member> members) async {
    final db = firestore;
    if (db == null) return false;

    try {
      // 게스트(G )는 당일 참석자일 뿐이므로 영구 마스터 명부에는 정회원만 저장
      final regularMembers = members.where((m) => !m.isGuest).toList();
      final membersData = regularMembers.map((m) => m.toMap()).toList();

      await db
          .collection('club_metadata')
          .doc('master_members')
          .set({
            'members': membersData,
            'totalCount': regularMembers.length,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('Firestore saveMasterMembers Error: $e');
      return false;
    }
  }

  /// 전체 정회원 명부(Master Members)를 단일 문서에서 1회 조회 (0원 무과금 최적화: 읽기 1회)
  Future<List<Member>?> fetchMasterMembers() async {
    final db = firestore;
    if (db == null) return null;

    try {
      final doc = await db
          .collection('club_metadata')
          .doc('master_members')
          .get()
          .timeout(const Duration(seconds: 8));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final rawList = data['members'] as List<dynamic>?;
        if (rawList != null) {
          return rawList
              .map((item) => Member.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Firestore fetchMasterMembers Error: $e');
      return null;
    }
  }
}
