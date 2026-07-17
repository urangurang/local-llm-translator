#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

REPO_DIR=${0:A:h:h}
INSTALL_DIR="${LOCAL_LLM_TRANSLATOR_HOME:-$HOME/.local/share/local-llm-translator}"
SERVICES_DIR="$HOME/Library/Services"
RAW_BASE="${LOCAL_LLM_TRANSLATOR_RAW_BASE:-https://raw.githubusercontent.com/USER/local-llm-translator/main}"
TEXT_SERVICE_NAME="Translate with translategemma"
OCR_SERVICE_NAME="Screenshot OCR Translate"
OLLAMA_MODEL="${OLLAMA_MODEL:-translategemma}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

if [ -z "${TEXT_SHORTCUT+x}" ]; then
  TEXT_SHORTCUT='@$x'
fi
if [ -z "${OCR_SHORTCUT+x}" ]; then
  OCR_SHORTCUT='@~^o'
fi

mkdir -p "$INSTALL_DIR" "$SERVICES_DIR"

install_file() {
  local name="$1"
  local local_path="$REPO_DIR/scripts/$name"
  local target_path="$INSTALL_DIR/$name"

  if [ -f "$local_path" ]; then
    cp "$local_path" "$target_path"
    return
  fi

  if [[ "$RAW_BASE" == *"/USER/"* ]]; then
    echo "Cannot find $local_path and LOCAL_LLM_TRANSLATOR_RAW_BASE is not configured." >&2
    echo "Clone the repo and run scripts/install.zsh, or set LOCAL_LLM_TRANSLATOR_RAW_BASE." >&2
    exit 1
  fi

  curl -fsSL "$RAW_BASE/scripts/$name" -o "$target_path"
}

install_file "translate_selection.zsh"
install_file "screenshot_ocr_translate.zsh"
install_file "ocr_vision.swift"
chmod +x "$INSTALL_DIR/translate_selection.zsh" "$INSTALL_DIR/screenshot_ocr_translate.zsh"

python3 - "$INSTALL_DIR" "$SERVICES_DIR" "$TEXT_SERVICE_NAME" "$OCR_SERVICE_NAME" "$TEXT_SHORTCUT" "$OCR_SHORTCUT" "$OLLAMA_MODEL" "$OLLAMA_HOST" <<'PY'
import plistlib
import shutil
import sys
import uuid
from pathlib import Path

install_dir = Path(sys.argv[1])
services_dir = Path(sys.argv[2])
text_service_name, ocr_service_name = sys.argv[3:5]
text_shortcut, ocr_shortcut = sys.argv[5:7]
ollama_model, ollama_host = sys.argv[7:9]


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


def write_workflow(name, input_type, command):
    workflow_dir = services_dir / f'{name}.workflow'
    if workflow_dir.exists():
        shutil.rmtree(workflow_dir)
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


env = f'''export OLLAMA_MODEL={ollama_model!r}
export OLLAMA_HOST={ollama_host!r}
'''
text_command = f'''#!/bin/zsh
{env}"{install_dir / 'translate_selection.zsh'}" "$@"
'''
ocr_command = f'''#!/bin/zsh
{env}"{install_dir / 'screenshot_ocr_translate.zsh'}"
'''

write_workflow(text_service_name, 'text', text_command)
write_workflow(ocr_service_name, 'none', ocr_command)

pbs_path = Path.home() / 'Library/Preferences/pbs.plist'
pbs_path.parent.mkdir(parents=True, exist_ok=True)
try:
    with pbs_path.open('rb') as f:
        pbs = plistlib.load(f)
except Exception:
    pbs = {}

status = pbs.setdefault('NSServicesStatus', {})
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

killall pbs 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

cat <<EOF
Installed Local LLM Translator.

Services:
  - $TEXT_SERVICE_NAME: Command + Shift + X
  - $OCR_SERVICE_NAME: Control + Option + Command + O

Install dir:
  $INSTALL_DIR

Before using it, make sure Ollama is running and the model exists:
  ollama pull $OLLAMA_MODEL

Logs:
  /tmp/translategemma.log
  /tmp/translategemma_ocr.log
EOF
