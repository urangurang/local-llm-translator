# Local LLM Translator for macOS

[한국어](README.ko.md) | English

macOS Automator services for local translation with Ollama.

It includes:

- Selected text translation from English, Korean, or Japanese
- Screenshot OCR translation using macOS Vision
- `lt` command line interface
- Local result pages with source text, translated text, history, and clipboard copy
- Keyboard shortcuts for both workflows

## Requirements

- macOS
- Ollama
- Python 3
- Swift command line tools, included with Xcode Command Line Tools, for macOS Vision OCR in screenshot translation
- A local Ollama translation model

The default model name is:

```zsh
translategemma
```

`translategemma:latest` is about 3.3 GB on disk in Ollama.

The installer checks for this model and pulls it if it is missing:

```zsh
ollama pull translategemma
```

## Install

One-line install:

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/install.zsh | zsh
```

Or clone the repo and run:

```zsh
git clone https://github.com/urangurang/local-llm-translator.git
cd local-llm-translator
zsh scripts/install.zsh
```

The installer:

- Checks macOS requirements
- Runs `ollama pull translategemma` by default if the model is missing
- Installs scripts to `~/.local/share/local-llm-translator`
- Installs the `lt` command to `~/.local/bin/lt`
- Creates Automator services in `~/Library/Services`
- Sets default keyboard shortcuts
- Warns if the requested shortcuts are already used by another macOS Service
- Backs up existing workflows before replacing them

### Install Options

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/install.zsh | \
  zsh -s -- --model translategemma --host http://127.0.0.1:11434
```

Useful options:

```text
--model NAME           Ollama model name
--host URL             Ollama host
--install-dir PATH     Install scripts somewhere else
--bin-dir PATH         Install the lt command somewhere else
--text-shortcut VALUE  macOS shortcut code
--ocr-shortcut VALUE   macOS shortcut code
--no-shortcuts         Do not write keyboard shortcuts
--no-pull-model        Skip ollama pull during install
```

## Shortcuts

| Service | Shortcut |
| --- | --- |
| Translate with translategemma | `Command + Shift + X` |
| Screenshot OCR Translate | `Control + Option + Command + O` |

You can change them in:

```text
System Settings → Keyboard → Keyboard Shortcuts → Services
```

## Usage

### Command Line

```zsh
lt doctor
lt server
lt stop
lt text "Hello"
lt ocr
```

`lt server` opens the translator UI with an empty source field.
By default, the result UI uses `http://127.0.0.1:57575/translation_result.html`.
Use `lt stop` to stop the local translator UI server.

If `lt` is not found after install, add `~/.local/bin` to your shell `PATH`.

### Selected Text Translation

Select text in any app, then press:

```text
Command + Shift + X
```

The service detects English, Korean, or Japanese and opens a local result page. You can also edit the source text and rerun translation with `Command + Enter`.

### Screenshot OCR Translation

Press:

```text
Control + Option + Command + O
```

Select a screen area. The service runs OCR through macOS Vision, translates the detected text, opens a result page, and copies the translation to the clipboard.

Press `Esc` during screenshot selection to cancel without an error.

## Configuration

Override the Ollama model or host during install:

```zsh
OLLAMA_MODEL=translategemma OLLAMA_HOST=http://127.0.0.1:11434 zsh scripts/install.zsh
```

Override shortcuts during install:

```zsh
TEXT_SHORTCUT='@$x' OCR_SHORTCUT='@~^o' zsh scripts/install.zsh
```

macOS shortcut symbols:

- `@` = Command
- `$` = Shift
- `~` = Option
- `^` = Control

## Logs

```zsh
tail -f /tmp/translategemma.log
tail -f /tmp/translategemma_ocr.log
```

## Uninstall

One-line uninstall:

```zsh
curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/uninstall.zsh | zsh
```

Or from a cloned repo:

```zsh
zsh scripts/uninstall.zsh
```

The uninstaller removes:

- `~/Library/Services/Translate with translategemma.workflow`
- `~/Library/Services/Screenshot OCR Translate.workflow`
- `~/.local/bin/lt`
- `~/.local/share/local-llm-translator`
- The two service shortcut entries from `~/Library/Preferences/pbs.plist`

## Notes

- The result page uses a tiny temporary local Python server so browser retranslation can call Ollama without `file://` CORS issues.
- The result server uses fixed port `57575` by default and stays alive until replaced by a new run or stopped with `lt stop`. Override it with `LT_RESULT_PORT`.
- All translation requests go to your local Ollama server.
- The installer writes Automator workflows to `~/Library/Services` and shortcut settings to `~/Library/Preferences/pbs.plist`.
- Shortcut conflict detection currently checks other macOS Services in `pbs.plist`. App-specific shortcuts may still conflict.

## License

MIT
