# Local LLM Translator for macOS

macOS Automator services for local translation with Ollama.

It includes:

- Selected text translation from English, Korean, or Japanese
- Screenshot OCR translation using macOS Vision
- Local result pages with source text, translated text, history, and clipboard copy
- Keyboard shortcuts for both workflows

## Requirements

- macOS
- Ollama
- Python 3
- Swift command line tools, included with Xcode Command Line Tools
- A local Ollama translation model

The default model name is:

```zsh
translategemma
```

Install or create the model before using the services:

```zsh
ollama pull translategemma
```

## Install

Clone the repo and run:

```zsh
zsh scripts/install.zsh
```

For public GitHub install, the intended one-liner will be:

```zsh
LOCAL_LLM_TRANSLATOR_RAW_BASE=https://raw.githubusercontent.com/urangurang/local-llm-translator/main \
  zsh -c "$(curl -fsSL https://raw.githubusercontent.com/urangurang/local-llm-translator/main/scripts/install.zsh)"
```

If the installer is run from a cloned repo, it uses the local files. If it is run from a one-liner, it downloads the remaining scripts from `LOCAL_LLM_TRANSLATOR_RAW_BASE`.

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

```zsh
zsh scripts/uninstall.zsh
```

## Notes

- The result page uses a tiny temporary local Python server so browser retranslation can call Ollama without `file://` CORS issues.
- The temporary result server shuts down automatically after five minutes.
- All translation requests go to your local Ollama server.
- The installer writes Automator workflows to `~/Library/Services` and shortcut settings to `~/Library/Preferences/pbs.plist`.

## License

MIT
