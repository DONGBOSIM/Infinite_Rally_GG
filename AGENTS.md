# 🏸 Infinite Rally GG (무한랠리) - Antigravity Agent Guidelines

이 파일은 Antigravity 에이전트가 집/회사 등 어떤 환경에서도 일관되게 개발을 수행할 수 있도록 정의된 프로젝트 전역 행동 지침(Rules)입니다.

---

## 🏛️ 프로젝트 핵심 아키텍처
1. **관리자용 앱 (`/admin_app`)**: Android Flutter App (Dart 3 / Flutter 3.24.5)
2. **회원용 실시간 웹 전광판 (`/web_viewer`)**: HTML / Vanilla JS (모바일 반응형 1페이지 웹)
3. **웹 호스팅**: **Firebase Hosting** (`https://infinite-rally-gg.web.app/`)
   - ⚠️ 과거 사용하던 GitHub Pages는 폐쇄되었으므로 관련 코드를 재생성하지 마세요.
4. **실시간 데이터베이스**: Firebase Cloud Firestore (`infinite-rally-gg`)
   - 당일 세션 단일 문서 (`daily_sessions/YYYY-MM-DD`) 실시간 동기화
5. **무과금(0원) 원칙**: 유료 서버나 결제 필요 서비스는 일절 사용하지 않으며 Spark 플랜 내에서 최적화합니다.

---

## ⚙️ 에이전트 표준 작업 프로세스 (반드시 준수)

### 1. 작업 시작 시 (최신 코드 동기화)
- 항상 다른 장소(집/회사)에서 푸시된 최신 코드가 있는지 먼저 확인하고 pull을 수행합니다:
  ```bash
  git pull origin main
  ```

### 2. 코드 수정 및 기능 구현 시
- 웹 전광판 기본 접속 주소는 항상 `https://infinite-rally-gg.web.app/` 입니다.
- 브라우저 기능(검색, 하이라이트, QR 모달 등)은 서버 비용이 발생하지 않도록 100% 클라이언트 사이드 JS로 처리합니다.
- 관리자 앱(Flutter) 빌드 및 코드는 기존 GitHub Actions (`build-apk.yml`) 환경과 충돌하지 않도록 버전을 유지합니다.

### 3. 작업 완료 후 (자동 커밋 & 푸시 원칙)
- 사용자가 요청한 구현이나 수정이 완료되면, 사용자에게 수동 커밋을 요구하지 말고 **에이전트가 직접 Git 작업을 원스톱으로 마무리**합니다:
  1. `git status`로 변경 파일 확인
  2. `git add <수정된 파일들>`
  3. 명확하고 표준적인 커밋 메시지 작성:
     - `feat: ...`, `fix: ...`, `chore: ...`
  4. `git commit -m "..."`
  5. `git push origin main`
- 푸시 후 GitHub Actions(Firebase Hosting 배포 또는 APK 빌드)가 성공적으로 트리거되었음을 사용자에게 친절히 보고합니다.
