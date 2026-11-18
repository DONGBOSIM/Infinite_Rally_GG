import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/member.dart';

/// 투표 캡처 사진에서 파싱된 개별 참석자 정보
class ParsedAttendeeCandidate {
  final String name; // 추출된 이름 (예: "심동보", "재호")
  final String gender; // 'M' 또는 'F'
  final String region; // 추출된 지역명 (예: "목동")
  final String rawLine; // 원본 라인 텍스트

  ParsedAttendeeCandidate({
    required this.name,
    this.gender = 'M',
    this.region = '',
    this.rawLine = '',
  });
}

class OcrResult {
  final List<Member> matchedMembers; // 기존 회원 명단에서 인식된 회원들
  final List<ParsedAttendeeCandidate> unmatchedCandidates; // 기존 명단에 매칭되지 않은 미등록 참석자들
  final List<String> potentialGuestNames; // 하위 호환용 미등록 참석자 이름들
  final Map<String, String> guestGenders; // 이름 -> 성별 ('M' / 'F')
  final Map<String, String> matchedOriginalNames; // 회원 ID -> 캡처에서 추출된 이름 (예: 성 생략 시 "재호")
  final String rawText; // 추출된 원본 텍스트

  OcrResult({
    required this.matchedMembers,
    this.unmatchedCandidates = const [],
    required this.potentialGuestNames,
    this.guestGenders = const {},
    this.matchedOriginalNames = const {},
    required this.rawText,
  });
}

class OcrService {
  final ImagePicker _picker = ImagePicker();

  /// 갤러리에서 이미지 1장 선택
  Future<XFile?> pickImageFromGallery() async {
    try {
      return await _picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      // ignore: avoid_print
      print('이미지 선택 실패: $e');
      return null;
    }
  }

  /// 카메라로 즉시 촬영
  Future<XFile?> pickImageFromCamera() async {
    try {
      return await _picker.pickImage(source: ImageSource.camera);
    } catch (e) {
      // ignore: avoid_print
      print('카메라 촬영 실패: $e');
      return null;
    }
  }

  /// 온디바이스 Google ML Kit (Korean)으로 투표 캡처 사진 정밀 분석
  Future<OcrResult> processVoteImage({
    required String imagePath,
    required List<Member> allMembers,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final rawText = recognizedText.text;

      // 1. 텍스트 라인 단위 수집
      final List<String> lines = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) lines.add(t);
        }
      }

      // 2. 투표 캡처 사진의 패턴 정밀 분석 (정규식 기반)
      // 패턴 A: 괄호 안 형태 -> 별명 (이름/성별/지역) 또는 별명(이름/성별)
      final patternBracket = RegExp(r'[\(\[\{]([^\)\]\}]+)[\)\]\}]');
      // 패턴 B: 괄호 없는 슬래시 형태 -> 이름/성별/지역 또는 이름/성별
      final patternSlash = RegExp(r'([가-힣]{2,4})\s*[/\|]\s*([남여]|남성|여성|M|F)\s*(?:[/\|]\s*([가-힣0-9]+))?');
      // 패턴 C: 슬래시 없는 공백 구분 형태 -> 김성훈 남 목5동
      final patternSpace = RegExp(r'([가-힣]{2,4})\s+([남여])\s+([가-힣0-9]+)');

      // 제외할 일반 단어 (지역명, 투표/시스템 단어, 나이대 등)
      final excludeNames = {
        '참석', '불참', '미정', '투표', '마감', '인원', '명', '게스트',
        '회원', '배드민턴', '민턴', '정기모임', '도우미', '운영자', '총무',
        '매니저', '금요일', '토요일', '일요일', '월요일', '화요일', '수요일', '목요일',
        '참여', '대기', '목동', '화곡', '화곡동', '강서', '강서구', '염창동',
        '우장산', '우장산동', '마곡', '노량진', '등촌', '등촌동', '양평동',
        '여의도', '여의도동', '까치산', '남성', '여성', '초반', '중반', '후반',
      };

      final List<ParsedAttendeeCandidate> candidates = [];
      final Set<String> processedNamesInPass = {};

      for (final line in lines) {
        bool matched = false;

        // 1) 괄호 안 파싱 시도 (예: "메르팽구 (심동보/남/목동)", "에즈맥 (재호/남/강서)")
        final bMatch = patternBracket.firstMatch(line);
        if (bMatch != null) {
          final content = bMatch.group(1)?.trim() ?? '';
          final parts = content.split(RegExp(r'[/\|]')).map((p) => p.trim()).toList();
          if (parts.length >= 2) {
            final name = parts[0];
            final genderRaw = parts[1];
            final region = parts.length >= 3 ? parts[2] : '';
            final isFemale = genderRaw == '여' || genderRaw == '여성' || genderRaw.toUpperCase() == 'F';
            final gender = isFemale ? 'F' : 'M';

            if (RegExp(r'^[가-힣]{2,4}$').hasMatch(name) && !excludeNames.contains(name)) {
              if (!processedNamesInPass.contains(name)) {
                processedNamesInPass.add(name);
                candidates.add(ParsedAttendeeCandidate(
                  name: name,
                  gender: gender,
                  region: region,
                  rawLine: line,
                ));
              }
              matched = true;
            }
          }
        }

        // 2) 괄호 없는 슬래시 파싱 시도 (예: "진정호/남/화곡동", "원예린/여/목동")
        if (!matched) {
          final sMatch = patternSlash.firstMatch(line);
          if (sMatch != null) {
            final name = sMatch.group(1)?.trim() ?? '';
            final genderRaw = sMatch.group(2)?.trim() ?? '';
            final region = sMatch.group(3)?.trim() ?? '';
            final isFemale = genderRaw == '여' || genderRaw == '여성' || genderRaw.toUpperCase() == 'F';
            final gender = isFemale ? 'F' : 'M';

            if (RegExp(r'^[가-힣]{2,4}$').hasMatch(name) && !excludeNames.contains(name)) {
              if (!processedNamesInPass.contains(name)) {
                processedNamesInPass.add(name);
                candidates.add(ParsedAttendeeCandidate(
                  name: name,
                  gender: gender,
                  region: region,
                  rawLine: line,
                ));
              }
              matched = true;
            }
          }
        }

        // 3) 슬래시 없는 공백 파싱 시도 (예: "김성훈 남 목5동")
        if (!matched) {
          final spMatch = patternSpace.firstMatch(line);
          if (spMatch != null) {
            final name = spMatch.group(1)?.trim() ?? '';
            final genderRaw = spMatch.group(2)?.trim() ?? '';
            final region = spMatch.group(3)?.trim() ?? '';
            final isFemale = genderRaw == '여' || genderRaw == '여성' || genderRaw.toUpperCase() == 'F';
            final gender = isFemale ? 'F' : 'M';

            if (RegExp(r'^[가-힣]{2,4}$').hasMatch(name) && !excludeNames.contains(name)) {
              if (!processedNamesInPass.contains(name)) {
                processedNamesInPass.add(name);
                candidates.add(ParsedAttendeeCandidate(
                  name: name,
                  gender: gender,
                  region: region,
                  rawLine: line,
                ));
              }
              matched = true;
            }
          }
        }
      }

      // 3. 기존 회원 목록과 대조 매칭
      final Set<String> matchedMemberIds = {};
      final List<Member> matchedList = [];
      final Map<String, String> matchedOriginalNames = {};
      final List<ParsedAttendeeCandidate> unmatchedCandidates = [];

      for (final candidate in candidates) {
        final candName = candidate.name;
        final candGender = candidate.gender;

        // 3-1. 이름 완전 일치 (Exact Match)
        Member? foundMember;
        for (final m in allMembers) {
          if (matchedMemberIds.contains(m.id)) continue;
          if (m.name.trim() == candName) {
            foundMember = m;
            break;
          }
        }

        // 3-2. 한국 이름 성(姓, 1글자) 생략 매칭 (Last Name Omitted Match)
        // 예: 사진 속 candName이 2글자("재호", "효선", "정현")이고, 기존 회원 이름이 3글자 이상이며 끝 2글자가 일치하는 경우
        if (foundMember == null && candName.length == 2) {
          final endMatches = allMembers.where((m) {
            if (matchedMemberIds.contains(m.id)) return false;
            final mName = m.name.trim();
            return mName.length >= 3 && mName.endsWith(candName);
          }).toList();

          if (endMatches.isNotEmpty) {
            // 성별이 일치하는 회원을 최우선 매칭
            final genderMatched = endMatches.where((m) => m.gender == candGender).toList();
            if (genderMatched.isNotEmpty) {
              foundMember = genderMatched.first;
            } else {
              foundMember = endMatches.first;
            }
          }
        }

        if (foundMember != null) {
          matchedMemberIds.add(foundMember.id);
          matchedList.add(foundMember);
          matchedOriginalNames[foundMember.id] = candName;
        } else {
          unmatchedCandidates.add(candidate);
        }
      }

      // 3-3. Fallback: 기존 회원 이름이 3글자 이상인 경우, 텍스트 라인에 독립적으로 온전히 포함되어 있는지 확인
      for (final m in allMembers) {
        if (matchedMemberIds.contains(m.id)) continue;
        final mName = m.name.trim();
        if (mName.length >= 3 && !excludeNames.contains(mName)) {
          if (rawText.contains(mName)) {
            matchedMemberIds.add(m.id);
            matchedList.add(m);
            matchedOriginalNames[m.id] = mName;
          }
        }
      }

      // 4. 게스트 후보 정리 (오직 패턴으로 파싱된 유효한 미등록 인원만 등록)
      final List<String> guestNames = [];
      final Map<String, String> guestGenders = {};

      for (final uc in unmatchedCandidates) {
        final gName = uc.name;
        // 기존 회원 이름에 없는지 재검증
        final isAlreadyMember = allMembers.any((m) => m.name.trim() == gName);
        if (!isAlreadyMember && !guestNames.contains(gName)) {
          guestNames.add(gName);
          guestGenders[gName] = uc.gender;
        }
      }

      return OcrResult(
        matchedMembers: matchedList,
        unmatchedCandidates: unmatchedCandidates,
        potentialGuestNames: guestNames,
        guestGenders: guestGenders,
        matchedOriginalNames: matchedOriginalNames,
        rawText: rawText,
      );
    } catch (e) {
      // ignore: avoid_print
      print('ML Kit OCR 분석 에러: $e');
      return OcrResult(
        matchedMembers: [],
        potentialGuestNames: [],
        rawText: '분석 중 오류 발생: $e',
      );
    } finally {
      await textRecognizer.close();
    }
  }
}
