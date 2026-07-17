#!/bin/zsh
set -euo pipefail

INSTALL_DIR="${LOCAL_LLM_TRANSLATOR_HOME:-$HOME/.local/share/local-llm-translator}"
SERVICES_DIR="$HOME/Library/Services"

rm -rf "$SERVICES_DIR/Translate with translategemma.workflow"
rm -rf "$SERVICES_DIR/Screenshot OCR Translate.workflow"
rm -rf "$INSTALL_DIR"

python3 - <<'PY'
import plistlib
from pathlib import Path

pbs_path = Path.home() / 'Library/Preferences/pbs.plist'
try:
    with pbs_path.open('rb') as f:
        pbs = plistlib.load(f)
except Exception:
    raise SystemExit(0)

status = pbs.get('NSServicesStatus', {})
for key in [
    '(null) - Translate with translategemma - runWorkflowAsService',
    '(null) - Screenshot OCR Translate - runWorkflowAsService',
]:
    status.pop(key, None)

with pbs_path.open('wb') as f:
    plistlib.dump(pbs, f)
PY

killall pbs 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "Uninstalled Local LLM Translator."
