# macOS용 Local LLM Translator

한국어 | [English](README.md)

Ollama를 사용하는 macOS Automator 로컬 번역 서비스입니다.

포함 기능:

- 영어, 한국어, 일본어 선택 텍스트 번역
- macOS Vision 기반 스크린샷 OCR 번역
- `lt` 커맨드라인 인터페이스
- 원문, 번역문, 히스토리, 클립보드 복사를 지원하는 로컬 결과 페이지
- 두 워크플로우용 키보드 단축키

## 요구사항

- macOS
- Ollama
- Python 3
- Xcode Command Line Tools에 포함된 Swift command line tools. 스크린샷 번역에서 macOS Vision OCR을 쓰기 위해 필요합니다.
- 로컬 Ollama 번역 모델

기본 모델 이름:

```zsh
translategemma
```

`translategemma:latest`는 Ollama 기준 디스크에서 약 3.3GB입니다.

인스톨러는 이 모델이 있는지 확인하고, 없으면 자동으로 pull합니다.

```zsh
ollama pull translategemma
```

## 설치

원라인 설치:

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/install.zsh | zsh
```

또는 repo를 clone해서 실행:

```zsh
git clone https://github.com/urangurang/local-llm-translator.git
cd local-llm-translator
zsh scripts/install.zsh
```

인스톨러가 하는 일:

- macOS 요구사항 확인
- 모델이 없으면 `ollama pull translategemma` 실행
- 스크립트를 `~/.local/share/local-llm-translator`에 설치
- `lt` 명령어를 `~/.local/bin/lt`에 설치
- Automator 서비스를 `~/Library/Services`에 생성
- 기본 키보드 단축키 설정
- 요청한 단축키가 다른 macOS Service에서 이미 사용 중이면 경고
- 기존 workflow가 있으면 백업 후 교체

### 설치 옵션

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/install.zsh | \
  zsh -s -- --model translategemma --host http://127.0.0.1:11434
```

주요 옵션:

```text
--model NAME           Ollama 모델 이름
--host URL             Ollama host
--install-dir PATH     스크립트 설치 위치 변경
--bin-dir PATH         lt 명령어 설치 위치 변경
--text-shortcut VALUE  텍스트 번역 단축키
--ocr-shortcut VALUE   OCR 번역 단축키
--no-shortcuts         키보드 단축키를 설정하지 않음
--no-pull-model        설치 중 ollama pull을 건너뜀
```

## 단축키

| Service | Shortcut |
| --- | --- |
| Translate with translategemma | `Command + Shift + X` |
| Screenshot OCR Translate | `Control + Option + Command + O` |

단축키는 macOS 설정에서 변경할 수 있습니다.

```text
System Settings → Keyboard → Keyboard Shortcuts → Services
```

## 사용법

### 커맨드라인

```zsh
lt doctor
lt server
lt stop
lt text "Hello"
lt ocr
```

`lt server`는 원문 입력칸이 비어 있는 번역 UI를 엽니다.
기본 결과 페이지 주소는 `http://127.0.0.1:57575/translation_result.html`입니다.
로컬 번역 UI 서버를 끄려면 `lt stop`을 사용하세요.

설치 후 `lt`를 찾을 수 없다면 shell `PATH`에 `~/.local/bin`을 추가하세요.

### 선택 텍스트 번역

아무 앱에서 텍스트를 선택한 뒤 누릅니다.

```text
Command + Shift + X
```

서비스가 영어, 한국어, 일본어를 감지하고 로컬 결과 페이지를 엽니다. 결과 페이지에서 원문을 직접 수정한 뒤 `Command + Enter`로 다시 번역할 수도 있습니다.

### 스크린샷 OCR 번역

다음 단축키를 누릅니다.

```text
Control + Option + Command + O
```

화면 영역을 선택하면 macOS Vision으로 OCR을 실행하고, 감지된 텍스트를 번역한 뒤 결과 페이지를 열고 번역문을 클립보드에 복사합니다.

영역 선택 중 `Esc`를 누르면 오류 없이 취소됩니다.

## 설정

설치 시 Ollama 모델이나 host를 바꿀 수 있습니다.

```zsh
OLLAMA_MODEL=translategemma OLLAMA_HOST=http://127.0.0.1:11434 zsh scripts/install.zsh
```

단축키도 바꿀 수 있습니다.

```zsh
TEXT_SHORTCUT='@$x' OCR_SHORTCUT='@~^o' zsh scripts/install.zsh
```

macOS 단축키 기호:

- `@` = Command
- `$` = Shift
- `~` = Option
- `^` = Control

## 로그

```zsh
tail -f /tmp/translategemma.log
tail -f /tmp/translategemma_ocr.log
```

## 삭제

원라인 삭제:

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/uninstall.zsh | zsh
```

또는 clone한 repo에서:

```zsh
zsh scripts/uninstall.zsh
```

삭제되는 항목:

- `~/Library/Services/Translate with translategemma.workflow`
- `~/Library/Services/Screenshot OCR Translate.workflow`
- `~/.local/bin/lt`
- `~/.local/share/local-llm-translator`
- `~/Library/Preferences/pbs.plist` 안의 두 서비스 단축키 항목

## 참고

- 결과 페이지는 작은 임시 로컬 Python 서버를 사용합니다. 브라우저에서 재번역할 때 `file://` CORS 문제를 피하기 위해서입니다.
- 결과 서버는 기본적으로 고정 포트 `57575`를 사용하고, 새 실행으로 교체되거나 `lt stop`으로 중지할 때까지 살아 있습니다. `LT_RESULT_PORT`로 포트를 바꿀 수 있습니다.
- 모든 번역 요청은 로컬 Ollama 서버로만 전송됩니다.
- 인스톨러는 Automator workflow를 `~/Library/Services`에 만들고, 단축키 설정을 `~/Library/Preferences/pbs.plist`에 씁니다.
- 단축키 충돌 감지는 `pbs.plist`의 다른 macOS Services만 확인합니다. 앱 내부 단축키와는 여전히 충돌할 수 있습니다.

## 라이선스

MIT
