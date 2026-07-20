#!/bin/zsh
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR=${0:A:h}
OLLAMA_MODEL="${OLLAMA_MODEL:-translategemma}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
LOG="/tmp/translategemma_ocr.log"
CAPTURE_PATH="/tmp/translategemma_ocr_capture.png"
ORIGINAL_PATH="/tmp/translategemma_ocr_original.txt"
RAW_ORIGINAL_PATH="/tmp/translategemma_ocr_original_raw.txt"
TRANSLATED_PATH="/tmp/translategemma_ocr_translated.txt"
RESPONSE_PATH="/tmp/translategemma_ocr_response.json"
HTML_PATH="/tmp/translategemma_ocr_result.html"

exec >> "$LOG" 2>&1
echo "----- $(date) -----"

rm -f "$CAPTURE_PATH" "$ORIGINAL_PATH" "$RAW_ORIGINAL_PATH" "$TRANSLATED_PATH" "$RESPONSE_PATH" "$HTML_PATH"

echo "Select a screen area for OCR..."
screencapture -i "$CAPTURE_PATH"

if [ ! -s "$CAPTURE_PATH" ]; then
  echo "No screenshot captured."
  exit 0
fi

OCR_TEXT=$(swift "$SCRIPT_DIR/ocr_vision.swift" "$CAPTURE_PATH")

printf '%s' "$OCR_TEXT" > "$RAW_ORIGINAL_PATH"

python3 - "$RAW_ORIGINAL_PATH" "$ORIGINAL_PATH" <<'PY'
import sys
import unicodedata

source_path, output_path = sys.argv[1:3]
text = open(source_path, encoding='utf-8').read()
text = unicodedata.normalize('NFC', text).strip()
with open(output_path, 'w', encoding='utf-8') as f:
    f.write(text)
PY

if [ ! -s "$ORIGINAL_PATH" ]; then
  echo "OCR returned empty text."
  osascript -e 'display alert "OCR 결과가 비어 있습니다." message "다시 더 선명한 영역을 선택해보세요."' >/dev/null 2>&1 || true
  exit 1
fi

LANG_CHECK=$(python3 - "$ORIGINAL_PATH" <<'PY'
import sys

text = open(sys.argv[1], encoding='utf-8').read()
ko = sum(1 for c in text if '\uAC00' <= c <= '\uD7A3')
ja_hira = sum(1 for c in text if '\u3040' <= c <= '\u309F')
ja_kata = sum(1 for c in text if '\u30A0' <= c <= '\u30FF')
cjk = sum(1 for c in text if '\u4E00' <= c <= '\u9FFF')
en = sum(1 for c in text if c.isascii() and c.isalpha())
ja = ja_hira + ja_kata
total = ko + ja + cjk + en

if total == 0:
    print('unknown')
elif ko / total >= 0.25:
    print('ko')
elif ja / total >= 0.10:
    print('ja')
elif en / total >= 0.50:
    print('en')
elif cjk > 0:
    print('ja')
else:
    print('unknown')
PY
)

case "$LANG_CHECK" in
  ko)
    TARGET_LANG="en"
    DIRECTION="🇰🇷 → 🇺🇸"
    ;;
  ja)
    TARGET_LANG="ko"
    DIRECTION="🇯🇵 → 🇰🇷"
    ;;
  en|unknown)
    TARGET_LANG="ko"
    DIRECTION="🇺🇸 → 🇰🇷"
    ;;
esac

python3 - "$ORIGINAL_PATH" "$LANG_CHECK" "$TARGET_LANG" > /tmp/translategemma_ocr_payload.json <<'PY'
import json
import os
import sys

source_path, source_lang, target_lang = sys.argv[1:4]
text = open(source_path, encoding='utf-8').read()
names = {'ko': 'Korean', 'en': 'English', 'ja': 'Japanese', 'unknown': 'the source language'}
source_name = names.get(source_lang, 'the source language')
target_name = names.get(target_lang, 'Korean')

payload = {
    'model': os.environ.get('OLLAMA_MODEL', 'translategemma'),
    'stream': False,
    'options': {
        'temperature': 0.2,
        'top_p': 0.85,
        'top_k': 40,
        'repeat_penalty': 1.05,
        'seed': 42,
        'num_ctx': 8192,
    },
    'messages': [
        {
            'role': 'system',
            'content': (
                'You are a professional Korean-English-Japanese translator. '
                'Return only the translated text. Do not include headings, labels, '
                'source text, explanations, markdown, or multiple alternatives.'
            ),
        },
        {
            'role': 'user',
            'content': f'Translate from {source_name} to {target_name}. Return only {target_name}.\n\n{text}',
        },
    ],
}

print(json.dumps(payload, ensure_ascii=False))
PY

if ! curl -sS --connect-timeout 3 --max-time 120 "$OLLAMA_HOST/api/chat" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/translategemma_ocr_payload.json \
  > "$RESPONSE_PATH"; then
  python3 - "$RESPONSE_PATH" "$OLLAMA_HOST" <<'PY'
import json
import sys
path, host = sys.argv[1:3]
payload = {
    'error': f'Could not reach Ollama at {host}',
    'kind': 'ollama_unreachable',
}
open(path, 'w', encoding='utf-8').write(json.dumps(payload, ensure_ascii=False))
PY
fi

python3 - "$RESPONSE_PATH" "$TRANSLATED_PATH" "$OLLAMA_MODEL" <<'PY'
import json
import sys
import unicodedata

response_path, translated_path, model = sys.argv[1:4]
try:
    data = json.load(open(response_path, encoding='utf-8'))
    if data.get('error'):
        message = str(data.get('error'))
        lower = message.lower()
        if data.get('kind') == 'ollama_unreachable' or 'connection refused' in lower or 'could not reach' in lower:
            text = (
                '번역 오류: Ollama가 꺼져 있거나 연결되지 않았습니다.\n\n'
                '1. Ollama 앱을 실행하거나 터미널에서 `ollama serve`를 실행하세요.\n'
                '2. `lt status`로 Ollama host가 ok인지 확인하세요.\n'
                '3. 다시 OCR 번역을 실행하세요.'
            )
        elif 'model' in lower and ('not found' in lower or 'pull' in lower):
            text = (
                f'번역 오류: Ollama 모델이 없습니다.\n\n'
                f'1. 터미널에서 `ollama pull {model}`을 실행하세요.\n'
                '2. `lt status`로 Model installed가 ok인지 확인하세요.\n'
                '3. 다시 OCR 번역을 실행하세요.'
            )
        else:
            text = f'번역 오류: Ollama 응답 오류\n\n{message}'
    else:
        text = data['message']['content'].strip()
except Exception as exc:
    raw = open(response_path, encoding='utf-8', errors='replace').read()[:1000]
    text = (
        '번역 오류: Ollama 응답을 읽지 못했습니다.\n\n'
        '1. `lt status`로 Ollama와 모델 상태를 확인하세요.\n'
        '2. `/tmp/translategemma_ocr_response.json`와 `/tmp/translategemma_ocr.log`를 확인하세요.\n\n'
        f'오류: {exc}\n\n응답 앞부분:\n{raw}'
    )

text = unicodedata.normalize('NFC', text)
with open(translated_path, 'w', encoding='utf-8') as f:
    f.write(text)
PY

python3 - "$TRANSLATED_PATH" <<'PY'
import subprocess
import sys
import unicodedata

text = unicodedata.normalize('NFC', open(sys.argv[1], encoding='utf-8').read())
subprocess.run(['pbcopy'], input=text.encode('utf-8'))
PY

python3 - "$CAPTURE_PATH" "$ORIGINAL_PATH" "$TRANSLATED_PATH" "$HTML_PATH" "$DIRECTION" <<'PY'
import base64
import html
import sys
from pathlib import Path

capture_path, original_path, translated_path, html_path, direction = sys.argv[1:6]
image_data = base64.b64encode(Path(capture_path).read_bytes()).decode('ascii')
original = html.escape(Path(original_path).read_text(encoding='utf-8'))
translated = html.escape(Path(translated_path).read_text(encoding='utf-8'))
direction = html.escape(direction)

doc = f'''<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OCR 번역 결과</title>
<style>
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    min-height: 100vh;
    padding: 28px;
    background: #eef0f5;
    color: #191927;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }}
  main {{
    max-width: 1180px;
    margin: 0 auto;
    background: #fff;
    border-radius: 18px;
    padding: 32px;
    box-shadow: 0 20px 50px rgba(25, 25, 39, 0.10);
  }}
  header {{
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 20px;
    margin-bottom: 28px;
  }}
  h1 {{
    margin: 0;
    font-size: 30px;
    letter-spacing: 0;
  }}
  .direction {{
    color: #6f7280;
    font-weight: 700;
  }}
  .grid {{
    display: grid;
    grid-template-columns: minmax(280px, 0.85fr) minmax(360px, 1.15fr);
    gap: 22px;
  }}
  .label {{
    margin: 0 0 10px;
    color: #8a8d9b;
    font-size: 13px;
    font-weight: 800;
  }}
  .shot {{
    width: 100%;
    max-height: 520px;
    object-fit: contain;
    background: #f6f7fb;
    border: 1px solid #e1e4ee;
    border-radius: 12px;
  }}
  .box {{
    white-space: pre-wrap;
    line-height: 1.75;
    font-size: 17px;
    border-radius: 12px;
    padding: 18px;
    border: 1px solid #e1e4ee;
    background: #f8f9fd;
  }}
  .translated {{
    background: #eef3ff;
    color: #11182f;
    border-color: #dde7ff;
  }}
  .stack {{
    display: grid;
    gap: 18px;
  }}
  footer {{
    display: flex;
    justify-content: space-between;
    margin-top: 22px;
    color: #22a05a;
    font-size: 13px;
    font-weight: 800;
  }}
  .model {{ color: #a3a5ad; }}
  @media (max-width: 860px) {{
    body {{ padding: 14px; }}
    main {{ padding: 22px; }}
    .grid {{ grid-template-columns: 1fr; }}
  }}
</style>
</head>
<body>
<main>
  <header>
    <h1>OCR 번역 결과</h1>
    <div class="direction">{direction}</div>
  </header>
  <div class="grid">
    <section>
      <p class="label">스크린샷</p>
      <img class="shot" src="data:image/png;base64,{image_data}" alt="Captured screenshot">
    </section>
    <section class="stack">
      <div>
        <p class="label">OCR 원문</p>
        <div class="box">{original}</div>
      </div>
      <div>
        <p class="label">번역</p>
        <div class="box translated">{translated}</div>
      </div>
    </section>
  </div>
  <footer>
    <span>클립보드에 복사됨</span>
    <span class="model">translategemma</span>
  </footer>
</main>
</body>
</html>'''

Path(html_path).write_text(doc, encoding='utf-8')
PY

open "$HTML_PATH"
echo "result=$HTML_PATH"
echo "log=$LOG"
