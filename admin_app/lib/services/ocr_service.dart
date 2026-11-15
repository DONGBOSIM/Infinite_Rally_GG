import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/member.dart';

class OcrResult {
  final List<Member> matchedMembers; // 기존 회원 명단에서 인식된 회원들
  final List<String> potentialGuestNames; // 기존 명단에 없지만 캡처에서 발견된 이름들
  final String rawText; // 추출된 원본 텍스트

  OcrResult({
    required this.matchedMembers,
    required this.potentialGuestNames,
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

  /// 온디바이스 Google ML Kit (Korean)으로 투표 캡처 사진 분석
  Future<OcrResult> processVoteImage({
    required String imagePath,
    required List<Member> allMembers,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.korean);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final rawText = recognizedText.text;

      final Set<String> matchedMemberIds = {};
      final List<Member> matchedList = [];
      final Set<String> guestCandidates = {};

      // 줄바꿈 및 공백 단위로 텍스트 라인 분석
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;

          // 1. 기존 회원 목록과 대조 (이름이 해당 라인에 정확히 또는 부분 포함되는지 확인)
          bool foundInMembers = false;
          for (final member in allMembers) {
            if (member.name.trim().isEmpty) continue;
            // 이름 검색 (예: "김랠리", "1. 김랠리", "김랠리 참석" 등)
            if (lineText.contains(member.name)) {
              if (!matchedMemberIds.contains(member.id)) {
                matchedMemberIds.add(member.id);
                matchedList.add(member);
              }
              foundInMembers = true;
            }
          }

          // 2. 기존 회원에 없고, 2~4글자의 한글 단어인 경우 게스트 후보로 등록
          if (!foundInMembers) {
            final words = lineText.split(RegExp(r'\s+'));
            for (final word in words) {
              final cleaned = word.replaceAll(RegExp(r'[^가-힣]'), '');
              // 투표 관련 단어(참석, 투표, 인원, 마감 등) 필터링
              final excludeWords = {'참석', '불참', '미정', '투표', '마감', '인원', '명', '게스트', '회원', '배드민턴', '정기모임'};
              if (cleaned.length >= 2 && cleaned.length <= 4 && !excludeWords.contains(cleaned)) {
                // 기존 회원 이름 중에 없는지 재확인
                final isMember = allMembers.any((m) => m.name == cleaned);
                if (!isMember) {
                  guestCandidates.add(cleaned);
                }
              }
            }
          }
        }
      }

      return OcrResult(
        matchedMembers: matchedList,
        potentialGuestNames: guestCandidates.toList(),
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

