#!/bin/zsh
set -euo pipefail

INSTALL_DIR="${LOCAL_LLM_TRANSLATOR_HOME:-$HOME/.local/share/local-llm-translator}"
BIN_DIR="${LOCAL_LLM_TRANSLATOR_BIN_DIR:-$HOME/.local/bin}"
SERVICES_DIR="$HOME/Library/Services"

rm -rf "$SERVICES_DIR/Translate with translategemma.workflow"
rm -rf "$SERVICES_DIR/Screenshot OCR Translate.workflow"
if [ -L "$BIN_DIR/lt" ]; then
  target=$(readlink "$BIN_DIR/lt")
  if [ "$target" = "$INSTALL_DIR/lt" ]; then
    rm -f "$BIN_DIR/lt"
  fi
fi
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

if not status:
    pbs['ServicesShortcutsPresent'] = False

with pbs_path.open('wb') as f:
    plistlib.dump(pbs, f)
PY

killall pbs 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "Uninstalled Local LLM Translator."
