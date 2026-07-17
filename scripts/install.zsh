#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

RAW_BASE_DEFAULT="https://raw.githubusercontent.com/urangurang/local-llm-translator/main"
RAW_BASE="${LOCAL_LLM_TRANSLATOR_RAW_BASE:-$RAW_BASE_DEFAULT}"
REPO_DIR=${0:A:h:h}
INSTALL_DIR="${LOCAL_LLM_TRANSLATOR_HOME:-$HOME/.local/share/local-llm-translator}"
SERVICES_DIR="$HOME/Library/Services"
TEXT_SERVICE_NAME="Translate with translategemma"
OCR_SERVICE_NAME="Screenshot OCR Translate"
OLLAMA_MODEL="${OLLAMA_MODEL:-translategemma}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
INSTALL_SHORTCUTS=1
PULL_MODEL=0
RESTART_SERVICES=1

if [ -z "${TEXT_SHORTCUT+x}" ]; then
  TEXT_SHORTCUT='@$x'
fi
if [ -z "${OCR_SHORTCUT+x}" ]; then
  OCR_SHORTCUT='@~^o'
fi

usage() {
  cat <<EOF
Local LLM Translator installer for macOS

Usage:
  zsh scripts/install.zsh [options]
  curl -fsSL $RAW_BASE_DEFAULT/scripts/install.zsh | zsh

Options:
  --model NAME           Ollama model name. Default: $OLLAMA_MODEL
  --host URL             Ollama host. Default: $OLLAMA_HOST
  --install-dir PATH     Install scripts here. Default: $INSTALL_DIR
  --text-shortcut VALUE  macOS shortcut code. Default: $TEXT_SHORTCUT
  --ocr-shortcut VALUE   macOS shortcut code. Default: $OCR_SHORTCUT
  --no-shortcuts         Install services without writing keyboard shortcuts
  --pull-model           Run 'ollama pull MODEL' during install
  --no-restart-services  Do not restart pbs/cfprefsd after install
  -h, --help             Show this help

macOS shortcut symbols:
  @ = Command, $ = Shift, ~ = Option, ^ = Control
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      OLLAMA_MODEL="${2:?missing value for --model}"
      shift 2
      ;;
    --host)
      OLLAMA_HOST="${2:?missing value for --host}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:?missing value for --install-dir}"
      shift 2
      ;;
    --text-shortcut)
      TEXT_SHORTCUT="${2:?missing value for --text-shortcut}"
      shift 2
      ;;
    --ocr-shortcut)
      OCR_SHORTCUT="${2:?missing value for --ocr-shortcut}"
      shift 2
      ;;
    --no-shortcuts)
      INSTALL_SHORTCUTS=0
      shift
      ;;
    --pull-model)
      PULL_MODEL=1
      shift
      ;;
    --no-restart-services)
      RESTART_SERVICES=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

info() { printf '==> %s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

require_command() {
  have "$1" || fail "Missing required command: $1"
}

if [ "$(uname -s)" != "Darwin" ]; then
  fail "This installer is macOS-only."
fi

info "Checking requirements"
require_command python3
require_command curl
require_command swift
require_command screencapture
require_command osascript
require_command pbcopy
require_command open

if have ollama; then
  if [ "$PULL_MODEL" -eq 1 ]; then
    info "Pulling Ollama model: $OLLAMA_MODEL"
    ollama pull "$OLLAMA_MODEL"
  elif curl -fsS "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    if ! ollama list | awk '{print $1}' | grep -qx "$OLLAMA_MODEL"; then
      warn "Ollama is running, but model '$OLLAMA_MODEL' was not found. Run: ollama pull $OLLAMA_MODEL"
    fi
  else
    warn "Could not reach Ollama at $OLLAMA_HOST. Start Ollama before using the services."
  fi
else
  warn "Ollama CLI was not found. Install Ollama and pull '$OLLAMA_MODEL' before using the services."
fi

info "Installing scripts to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$SERVICES_DIR"

install_file() {
  local name="$1"
  local local_path="$REPO_DIR/scripts/$name"
  local target_path="$INSTALL_DIR/$name"

  if [ -f "$local_path" ]; then
    cp "$local_path" "$target_path"
    return
  fi

  info "Downloading $name"
  curl -fsSL "$RAW_BASE/scripts/$name" -o "$target_path"
}

install_file "translate_selection.zsh"
install_file "screenshot_ocr_translate.zsh"
install_file "ocr_vision.swift"
chmod +x "$INSTALL_DIR/translate_selection.zsh" "$INSTALL_DIR/screenshot_ocr_translate.zsh"

info "Creating Automator services"
python3 - "$INSTALL_DIR" "$SERVICES_DIR" "$TEXT_SERVICE_NAME" "$OCR_SERVICE_NAME" "$TEXT_SHORTCUT" "$OCR_SHORTCUT" "$OLLAMA_MODEL" "$OLLAMA_HOST" "$INSTALL_SHORTCUTS" <<'PY'
import plistlib
import shutil
import sys
import uuid
from datetime import datetime
from pathlib import Path

install_dir = Path(sys.argv[1])
services_dir = Path(sys.argv[2])
text_service_name, ocr_service_name = sys.argv[3:5]
text_shortcut, ocr_shortcut = sys.argv[5:7]
ollama_model, ollama_host = sys.argv[7:9]
install_shortcuts = sys.argv[9] == '1'


def zsh_quote(value):
    return "'" + str(value).replace("'", "'\\''") + "'"


def run_shell_action(command):
    return {
        'action': {
            'AMAccepts': {'Container': 'List', 'Optional': True, 'Types': ['com.apple.cocoa.string']},
            'AMActionVersion': '2.0.3',
            'AMApplication': ['Automator'],
            'AMParameterProperties': {
                'COMMAND_STRING': {},
                'CheckedForUserDefaultShell': {},
                'inputMethod': {},
                'shell': {},
                'source': {},
            },
            'AMProvides': {'Container': 'List', 'Types': ['com.apple.cocoa.string']},
            'ActionBundlePath': '/System/Library/Automator/Run Shell Script.action',
            'ActionName': 'Run Shell Script',
            'ActionParameters': {
                'COMMAND_STRING': command,
                'CheckedForUserDefaultShell': True,
                'inputMethod': 1,
                'shell': '/bin/zsh',
                'source': '',
            },
            'BundleIdentifier': 'com.apple.RunShellScript',
            'CFBundleVersion': '2.0.3',
            'CanShowSelectedItemsWhenRun': False,
            'CanShowWhenRun': True,
            'Category': ['AMCategoryUtilities'],
            'Class Name': 'RunShellScriptAction',
            'InputUUID': str(uuid.uuid4()).upper(),
            'Keywords': ['Shell', 'Script', 'Command', 'Run', 'Unix'],
            'OutputUUID': str(uuid.uuid4()).upper(),
            'UUID': str(uuid.uuid4()).upper(),
            'UnlocalizedApplications': ['Automator'],
            'arguments': {
                '0': {'default value': 0, 'name': 'inputMethod', 'required': '0', 'type': '0', 'uuid': '0'},
                '1': {'default value': False, 'name': 'CheckedForUserDefaultShell', 'required': '0', 'type': '0', 'uuid': '1'},
                '2': {'default value': '', 'name': 'source', 'required': '0', 'type': '0', 'uuid': '2'},
                '3': {'default value': '', 'name': 'COMMAND_STRING', 'required': '0', 'type': '0', 'uuid': '3'},
                '4': {'default value': '/bin/sh', 'name': 'shell', 'required': '0', 'type': '0', 'uuid': '4'},
            },
            'isViewVisible': 1,
            'location': '421.250000:305.000000',
            'nibPath': '/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib',
        }
    }


def workflow_meta(input_type):
    is_text = input_type == 'text'
    automator_type = 'com.apple.Automator.text' if is_text else 'com.apple.Automator.nothing'
    return {
        'applicationBundleIDsByPath': {},
        'applicationPaths': [],
        'inputTypeIdentifier': automator_type,
        'outputTypeIdentifier': 'com.apple.Automator.nothing',
        'presentationMode': 11,
        'processesInput': False,
        'serviceInputTypeIdentifier': automator_type,
        'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing',
        'serviceProcessesInput': False,
        'systemImageName': 'NSActionTemplate',
        'useAutomaticInputType': False,
        'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
    }


def info_plist(name, input_type):
    send_types = ['public.utf8-plain-text'] if input_type == 'text' else []
    return {
        'NSServices': [{
            'NSBackgroundColorName': 'background',
            'NSIconName': 'NSActionTemplate',
            'NSMenuItem': {'default': name},
            'NSMessage': 'runWorkflowAsService',
            'NSSendTypes': send_types,
        }]
    }


def backup_path(path):
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    return path.with_name(f'{path.name}.backup-{stamp}')


def write_workflow(name, input_type, command):
    workflow_dir = services_dir / f'{name}.workflow'
    if workflow_dir.exists():
        backup = backup_path(workflow_dir)
        shutil.move(str(workflow_dir), str(backup))
        print(f'Backed up existing workflow: {backup}')

    contents = workflow_dir / 'Contents'
    contents.mkdir(parents=True)
    document = {
        'AMApplicationBuild': '534',
        'AMApplicationVersion': '2.10',
        'AMDocumentVersion': '2',
        'actions': [run_shell_action(command)],
        'connectors': {},
        'workflowMetaData': workflow_meta(input_type),
    }
    with (contents / 'document.wflow').open('wb') as f:
        plistlib.dump(document, f)
    with (contents / 'Info.plist').open('wb') as f:
        plistlib.dump(info_plist(name, input_type), f)


env = f'''export OLLAMA_MODEL={zsh_quote(ollama_model)}
export OLLAMA_HOST={zsh_quote(ollama_host)}
'''
text_command = f'''#!/bin/zsh
{env}"{install_dir / 'translate_selection.zsh'}" "$@"
'''
ocr_command = f'''#!/bin/zsh
{env}"{install_dir / 'screenshot_ocr_translate.zsh'}"
'''

write_workflow(text_service_name, 'text', text_command)
write_workflow(ocr_service_name, 'none', ocr_command)

if install_shortcuts:
    pbs_path = Path.home() / 'Library/Preferences/pbs.plist'
    pbs_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if pbs_path.exists():
            pbs_backup = backup_path(pbs_path)
            shutil.copy2(pbs_path, pbs_backup)
            print(f'Backed up shortcut preferences: {pbs_backup}')
        with pbs_path.open('rb') as f:
            pbs = plistlib.load(f)
    except Exception:
        pbs = {}

    status = pbs.setdefault('NSServicesStatus', {})
    managed_keys = {
        f'(null) - {text_service_name} - runWorkflowAsService',
        f'(null) - {ocr_service_name} - runWorkflowAsService',
    }
    requested = [
        (text_service_name, text_shortcut),
        (ocr_service_name, ocr_shortcut),
    ]

    if text_shortcut and ocr_shortcut and text_shortcut == ocr_shortcut:
        print(f'Warning: both Local LLM Translator services are using the same shortcut: {text_shortcut}')

    for service_name, shortcut in requested:
        if not shortcut:
            continue
        conflicts = []
        for existing_name, existing_item in status.items():
            if existing_name in managed_keys or not isinstance(existing_item, dict):
                continue
            if existing_item.get('key_equivalent') == shortcut:
                conflicts.append(existing_name)
        for conflict in conflicts:
            print(f'Warning: shortcut {shortcut} for "{service_name}" is already used by: {conflict}')

    for service_name, shortcut in [(text_service_name, text_shortcut), (ocr_service_name, ocr_shortcut)]:
        status[f'(null) - {service_name} - runWorkflowAsService'] = {
            'key_equivalent': shortcut,
            'presentation_modes': {
                'ContextMenu': True,
                'ServicesMenu': True,
                'TouchBar': True,
            },
        }
    pbs['ServicesShortcutsPresent'] = True
    with pbs_path.open('wb') as f:
        plistlib.dump(pbs, f)
PY

plutil -lint "$SERVICES_DIR/$TEXT_SERVICE_NAME.workflow/Contents/document.wflow" >/dev/null
plutil -lint "$SERVICES_DIR/$OCR_SERVICE_NAME.workflow/Contents/document.wflow" >/dev/null

if [ "$RESTART_SERVICES" -eq 1 ]; then
  info "Refreshing macOS Services cache"
  killall pbs 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true
fi

text_shortcut_label="Command + Shift + X"
ocr_shortcut_label="Control + Option + Command + O"
if [ "$INSTALL_SHORTCUTS" -eq 0 ]; then
  text_shortcut_label="not modified"
  ocr_shortcut_label="not modified"
fi

cat <<EOF

Installed Local LLM Translator.

Services:
  - $TEXT_SERVICE_NAME: $text_shortcut_label
  - $OCR_SERVICE_NAME: $ocr_shortcut_label

Install dir:
  $INSTALL_DIR

Ollama:
  model: $OLLAMA_MODEL
  host:  $OLLAMA_HOST

Try it:
  1. Start Ollama.
  2. Make sure the model exists: ollama pull $OLLAMA_MODEL
  3. Select text and run "$TEXT_SERVICE_NAME" from the Services menu.
  4. Run "$OCR_SERVICE_NAME" for screenshot OCR translation.

Logs:
  /tmp/translategemma.log
  /tmp/translategemma_ocr.log
EOF
