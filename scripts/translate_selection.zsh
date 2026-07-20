#!/bin/zsh
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
OLLAMA_HOST=${OLLAMA_HOST:-http://127.0.0.1:11434}
OLLAMA_MODEL=${OLLAMA_MODEL:-translategemma}

LOG="/tmp/translategemma.log"
exec >> "$LOG" 2>&1
echo "----- $(date) -----"

# NFC 변환해서 저장
echo "$*" | python3 -c "
import sys, unicodedata
text = unicodedata.normalize('NFC', sys.stdin.read().strip())
with open('/tmp/original.txt', 'w', encoding='utf-8') as f:
    f.write(text)
"

CLEAN_INPUT=$(python3 - <<'PYEOF'
import unicodedata
text = open('/tmp/original.txt', encoding='utf-8').read()
text = unicodedata.normalize('NFC', text).translate({13: 32, 10: 32})
print(' '.join(text.split()))
PYEOF
)

# 언어 판별
LANG_CHECK=$(python3 -c "
text = open('/tmp/original.txt', encoding='utf-8').read()

ko = sum(1 for c in text if '\uAC00' <= c <= '\uD7A3')
ja_hira = sum(1 for c in text if '\u3040' <= c <= '\u309F')
ja_kata = sum(1 for c in text if '\u30A0' <= c <= '\u30FF')
cjk = sum(1 for c in text if '\u4E00' <= c <= '\u9FFF')
en = sum(1 for c in text if c.isascii() and c.isalpha())

ja = ja_hira + ja_kata
scores = {'ko': ko, 'ja': ja, 'en': en}
total = ko + ja + en

if total == 0:
    print('ja' if cjk > 0 else 'unknown')
else:
    lang, count = max(scores.items(), key=lambda item: item[1])
    ratio = count / total

    if count >= 6 and ratio >= 0.45:
        print(lang)
    elif count >= 3 and ratio >= 0.65:
        print(lang)
    elif cjk > 0 and en == 0 and ko == 0:
        print('ja')
    else:
        print(lang)
")
if [ "$LANG_CHECK" = "ko" ]; then
    PROMPT="Translate the source text from Korean (ko) to English (en). Output only the English translation. Do not include the source text, language labels, markdown, quotes, explanations, alternatives, or multiple versions."
    DIRECTION="🇰🇷 → 🇺🇸"
    SOURCE_LANG="ko"
    TARGET_LANG="en"
elif [ "$LANG_CHECK" = "ja" ]; then
    PROMPT="Translate the source text from Japanese (ja) to Korean (ko). Output only the Korean translation. Do not include the source text, language labels, markdown, quotes, explanations, alternatives, or multiple versions."
    DIRECTION="🇯🇵 → 🇰🇷"
    SOURCE_LANG="ja"
    TARGET_LANG="ko"
elif [ "$LANG_CHECK" = "en" ]; then
    PROMPT="Translate the source text from English (en) to Korean (ko). Output only the Korean translation. Do not include the source text, language labels, markdown, quotes, explanations, alternatives, or multiple versions."
    DIRECTION="🇺🇸 → 🇰🇷"
    SOURCE_LANG="en"
    TARGET_LANG="ko"
else
    PROMPT="Detect the source language and translate it into Korean (ko). Output only the Korean translation. Do not include the source text, language labels, markdown, quotes, explanations, alternatives, or multiple versions."
    DIRECTION="Auto → 🇰🇷"
    SOURCE_LANG="auto"
    TARGET_LANG="ko"
fi
printf '%s' "$DIRECTION" > /tmp/direction.txt
printf '%s' "$SOURCE_LANG" > /tmp/source_lang.txt
printf '%s' "$TARGET_LANG" > /tmp/target_lang.txt

SKIP_INITIAL_TRANSLATION=0
if [ ! -s /tmp/original.txt ]; then
    SKIP_INITIAL_TRANSLATION=1
    printf '%s' '' > /tmp/translated.txt
fi

if [ "$SKIP_INITIAL_TRANSLATION" -eq 0 ]; then
printf '%s' "$PROMPT" > /tmp/translategemma_prompt.txt

PAYLOAD=$(python3 - <<'PYEOF'
import json
import os
import unicodedata
prompt = open('/tmp/translategemma_prompt.txt', encoding='utf-8').read()
text = open('/tmp/original.txt', encoding='utf-8').read()
text = unicodedata.normalize('NFC', text).translate({13: 32, 10: 32})
clean_input = ' '.join(text.split())
payload = {
    "model": os.environ.get("OLLAMA_MODEL", "translategemma"),
    "stream": False,
    "options": {
        "temperature": 0.2,
        "top_p": 0.85,
        "top_k": 40,
        "repeat_penalty": 1.05,
        "seed": 42,
        "num_ctx": 8192,
    },
    "messages": [
        {
            "role": "system",
            "content": "You are a translation engine. Return exactly one translation in the requested target language and nothing else. Never include the source text, language labels, markdown headings, quotes around the whole answer, explanations, alternatives, or multiple language versions.",
        },
        {
            "role": "user",
            "content": prompt + "\n\n" + clean_input,
        },
    ],
}
print(json.dumps(payload, ensure_ascii=False))
PYEOF
)

printf '%s
' "Payload bytes: ${#PAYLOAD}"

if ! RESPONSE=$(printf '%s' "$PAYLOAD" | curl -sS --connect-timeout 3 --max-time 120 "$OLLAMA_HOST/api/chat" \
  -H "Content-Type: application/json" \
  --data-binary @-); then
  RESPONSE=$(python3 - "$OLLAMA_HOST" <<'PYEOF'
import json
import sys
host = sys.argv[1]
print(json.dumps({
    'kind': 'ollama_unreachable',
    'error': f'Could not reach Ollama at {host}',
}, ensure_ascii=False))
PYEOF
)
fi

printf '%s' "$RESPONSE" > /tmp/translategemma_response.json

TRANSLATED=$(python3 - "$OLLAMA_MODEL" <<'PYEOF'
import json
import sys
from pathlib import Path
model = sys.argv[1]
raw = Path('/tmp/translategemma_response.json').read_text(encoding='utf-8', errors='replace')
try:
    data = json.loads(raw)
    if data.get('error'):
        message = str(data.get('error'))
        lower = message.lower()
        if data.get('kind') == 'ollama_unreachable' or 'connection refused' in lower or 'could not reach' in lower:
            print('번역 오류: Ollama가 꺼져 있거나 연결되지 않았습니다.')
            print()
            print('1. Ollama 앱을 실행하거나 터미널에서 `ollama serve`를 실행하세요.')
            print('2. `lt status`로 Ollama host가 ok인지 확인하세요.')
            print('3. 다시 번역을 실행하세요.')
            sys.exit(0)
        if 'model' in lower and ('not found' in lower or 'pull' in lower):
            print('번역 오류: Ollama 모델이 없습니다.')
            print()
            print(f'1. 터미널에서 `ollama pull {model}`을 실행하세요.')
            print('2. `lt status`로 Model installed가 ok인지 확인하세요.')
            print('3. 다시 번역을 실행하세요.')
            sys.exit(0)
        print('번역 오류: Ollama 응답 오류')
        print()
        print(message)
        sys.exit(0)
    target = Path('/tmp/target_lang.txt').read_text(encoding='utf-8').strip()
    text = data['message']['content']
    labels = {
        'ko': ['Korean', '한국어', 'Korea'],
        'en': ['English', '영어'],
        'ja': ['Japanese', '日本語', '일본어'],
    }
    all_labels = ['Korean', '한국어', 'English', '영어', 'Japanese', '日本語', '일본어']
    lines = text.splitlines()
    chunks = []
    current = None
    for line in lines:
        stripped = line.strip().strip('*').strip()
        matched = None
        for label in all_labels:
            if stripped.lower() in (label.lower() + ':', label.lower()):
                matched = label
                break
        if matched:
            current = []
            chunks.append((matched, current))
        elif current is not None:
            current.append(line)
    target_labels = [label.lower() for label in labels.get(target, [])]
    for label, chunk in chunks:
        if label.lower() in target_labels:
            cleaned = '\n'.join(chunk).strip()
            if cleaned:
                text = cleaned
                break
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in '"“”':
        text = text[1:-1].strip()
    print(text)
except Exception as exc:
    print('번역 오류: Ollama 응답을 JSON으로 읽지 못했습니다.')
    print('/tmp/translategemma_response.json 와 /tmp/translategemma.log 를 확인하세요.')
    print(f'오류: {exc}')
    print('응답 앞부분:')
    print(raw[:1000])
    sys.exit(1)
PYEOF
)

printf '%s' "$TRANSLATED" > /tmp/translated.txt

# 클립보드에 복사
python3 -c "
import subprocess, unicodedata
text = unicodedata.normalize('NFC', open('/tmp/translated.txt', encoding='utf-8').read())
subprocess.run(['pbcopy'], input=text.encode('utf-8'))
"
fi

python3 - << 'PYEOF'
import html as htmllib
import unicodedata
import json
import os

original = open('/tmp/original.txt', encoding='utf-8').read()
translated = unicodedata.normalize('NFC', open('/tmp/translated.txt', encoding='utf-8').read())
direction = open('/tmp/direction.txt', encoding='utf-8').read().strip()
source_lang = open('/tmp/source_lang.txt', encoding='utf-8').read().strip()
target_lang = open('/tmp/target_lang.txt', encoding='utf-8').read().strip()

history_path = '/tmp/translategemma_history.json'

def load_history():
    try:
        with open(history_path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []

history = load_history()
if original.strip() and translated.strip():
    item = {
        'id': str(int(__import__('time').time() * 1000)),
        'createdAt': __import__('datetime').datetime.now().isoformat(timespec='seconds'),
        'source': source_lang,
        'target': target_lang,
        'direction': direction,
        'original': original,
        'translated': translated,
    }
    history = [h for h in history if not (
        h.get('original') == item['original']
        and h.get('translated') == item['translated']
        and h.get('source') == item['source']
        and h.get('target') == item['target']
    )]
    history.insert(0, item)
    history = history[:50]
    try:
        with open(history_path, 'w', encoding='utf-8') as f:
            json.dump(history, f, ensure_ascii=False)
    except Exception:
        pass

original_json = json.dumps(original, ensure_ascii=False)
translated_json = json.dumps(translated, ensure_ascii=False)
direction_json = json.dumps(direction, ensure_ascii=False)
source_json = json.dumps(source_lang, ensure_ascii=False)
target_json = json.dumps(target_lang, ensure_ascii=False)
model_name = os.environ.get('OLLAMA_MODEL', 'translategemma')
model_json = json.dumps(model_name, ensure_ascii=False)
model_label = htmllib.escape(model_name)
history_json = json.dumps(history, ensure_ascii=False)

html = '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>번역 결과</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #f0f0f5;
    color: #1a1a2e;
    min-height: 100vh;
    padding: 30px 20px;
  }
  .app-shell {
    display: grid;
    grid-template-columns: 360px minmax(0, 1fr);
    gap: 18px;
    width: min(1440px, 100%);
    margin: 0 auto;
    align-items: start;
  }
  .history-panel, .card {
    background: white;
    border-radius: 16px;
    box-shadow: 0 4px 24px rgba(0,0,0,0.1);
  }
  .history-panel {
    position: sticky;
    top: 24px;
    max-height: calc(100vh - 60px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .history-header {
    padding: 18px 18px 12px;
    border-bottom: 1px solid #eeeef6;
  }
  .history-title { font-size: 15px; font-weight: 800; color: #1a1a2e; }
  .history-subtitle { margin-top: 4px; font-size: 11px; color: #9a9aa8; font-weight: 700; }
  .history-tools {
    display: grid;
    gap: 8px;
    padding: 12px;
    border-bottom: 1px solid #eeeef6;
  }
  .history-search {
    width: 100%;
    height: 36px;
    border: 1px solid #d9d9e6;
    border-radius: 9px;
    padding: 0 11px;
    font: inherit;
    font-size: 13px;
    outline: none;
  }
  .history-search:focus {
    border-color: #335cff;
    box-shadow: 0 0 0 3px rgba(51, 92, 255, 0.1);
  }
  .history-filter-row {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .history-filter {
    min-height: 28px;
    border: 1px solid #d9d9e6;
    border-radius: 8px;
    background: white;
    color: #45495a;
    padding: 0 9px;
    font-size: 12px;
    font-weight: 800;
    cursor: pointer;
  }
  .history-filter.active {
    border-color: #335cff;
    background: #335cff;
    color: white;
  }
  .history-count { font-size: 11px; color: #9a9aa8; font-weight: 700; }
  .history-list {
    display: grid;
    gap: 8px;
    overflow-y: auto;
    padding: 12px;
  }
  .history-empty { padding: 18px 6px; color: #8c8c99; font-size: 13px; line-height: 1.5; }
  .history-item {
    width: 100%;
    text-align: left;
    border: 1px solid #ececf5;
    border-radius: 10px;
    background: #fbfbfe;
    padding: 10px;
    cursor: pointer;
    display: grid;
    grid-template-columns: minmax(0, 1fr) 28px;
    gap: 8px;
    align-items: start;
  }
  .history-item:hover { border-color: #9ba8ff; background: #f6f7ff; }
  .history-item.active { border-color: #335cff; background: #f0f4ff; }
  .history-main { display: grid; gap: 6px; min-width: 0; }
  .history-delete {
    width: 28px;
    height: 28px;
    border: 1px solid transparent;
    border-radius: 7px;
    background: transparent;
    color: #9a9aa8;
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
  }
  .history-delete:hover {
    border-color: #ffd0d0;
    background: #fff0f0;
    color: #d93f3f;
  }
  .history-route { font-size: 12px; font-weight: 800; color: #335cff; }
  .history-original { font-size: 12px; color: #2a2d3c; line-height: 1.35; }
  .history-translated { font-size: 11px; color: #7d8190; line-height: 1.35; }
  .history-time { font-size: 10px; color: #aaa; font-weight: 700; }
  .card {
    padding: 28px;
    min-width: 0;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 16px;
    margin-bottom: 20px;
  }
  .title { font-size: 22px; font-weight: 800; color: #1a1a2e; }
  .direction { font-size: 14px; color: #666; white-space: nowrap; }
  .controls {
    display: grid;
    gap: 14px;
    background: #f8f8fc;
    border: 1px solid #ececf5;
    border-radius: 12px;
    padding: 14px;
    margin-bottom: 18px;
  }
  .field { display: grid; gap: 8px; }
  .field label, .label {
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #8c8c99;
  }
  .language-row {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 8px;
  }
  .target-row { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .lang-button, .action-button {
    min-height: 38px;
    border-radius: 9px;
    border: 1px solid #d9d9e6;
    background: white;
    color: #1f2333;
    font-size: 14px;
    font-weight: 700;
    cursor: pointer;
    transition: background 0.16s ease, border-color 0.16s ease, color 0.16s ease, box-shadow 0.16s ease;
  }
  .lang-button:hover, .action-button:hover { border-color: #9ba8ff; }
  .lang-button.active, .action-button.primary {
    border-color: #335cff;
    background: #335cff;
    color: white;
    box-shadow: 0 5px 14px rgba(51, 92, 255, 0.22);
  }
  .lang-button:disabled, .action-button:disabled {
    cursor: wait;
    opacity: 0.72;
  }
  .source-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    margin-bottom: 8px;
  }
  .action-button {
    min-width: 96px;
    padding: 0 14px;
  }
  .status-line {
    min-height: 18px;
    font-size: 12px;
    color: #6b6f80;
    font-weight: 700;
  }
  .advice-panel {
    display: none;
    border: 1px solid #ffd5d5;
    background: #fff7f7;
    color: #5a1d1d;
    border-radius: 10px;
    padding: 12px 14px;
    font-size: 13px;
    line-height: 1.55;
  }
  .advice-panel.visible { display: grid; gap: 8px; }
  .advice-title { font-weight: 800; color: #b42318; }
  .advice-panel ol { margin: 0; padding-left: 18px; }
  .advice-panel code {
    background: #fff;
    border: 1px solid #f0cdcd;
    border-radius: 5px;
    padding: 1px 5px;
    color: #3b1a1a;
  }
  .section { margin-bottom: 16px; }
  .text-box, .source-input {
    background: #f8f8fc;
    border-radius: 10px;
    padding: 16px;
    font-size: 15px;
    line-height: 1.7;
    color: #333;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .source-input {
    width: 100%;
    min-height: 132px;
    resize: vertical;
    border: 1px solid #e2e3ef;
    font-family: inherit;
    outline: none;
  }
  .source-input:focus {
    border-color: #335cff;
    box-shadow: 0 0 0 3px rgba(51, 92, 255, 0.12);
  }
  .translated { background: #f0f4ff; color: #1a1a2e; }
  .footer {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    margin-top: 20px;
  }
  .status { font-size: 12px; color: #22a05a; font-weight: 700; }
  .status.error { color: #d93f3f; }
  .model { font-size: 11px; color: #aaa; }
  @media (max-width: 860px) {
    body { padding: 14px; }
    .app-shell { grid-template-columns: 1fr; }
    .history-panel { position: static; max-height: 260px; }
    .card { padding: 20px; border-radius: 14px; }
    .header { align-items: flex-start; }
    .language-row, .target-row { grid-template-columns: 1fr; }
    .source-header { align-items: flex-start; flex-direction: column; }
    .action-button { width: 100%; }
    .footer { align-items: flex-start; flex-direction: column; }
  }
</style>
</head>
<body>
<div class="app-shell">
  <aside class="history-panel" aria-label="번역 히스토리">
    <div class="history-header">
      <div class="history-title">히스토리</div>
      <div class="history-subtitle">최근 번역 50개</div>
    </div>
    <div class="history-tools">
      <input class="history-search" id="historySearch" type="search" placeholder="히스토리 검색" autocomplete="off">
      <div class="history-filter-row" id="historyFilters"></div>
      <div class="history-count" id="historyCount"></div>
    </div>
    <div class="history-list" id="historyList"></div>
  </aside>
  <main class="card">
  <div class="header">
    <span class="title">번역 결과</span>
    <span class="direction" id="directionText"></span>
  </div>

  <div class="controls">
    <div class="field">
      <label>원문 언어</label>
      <div class="language-row" id="sourceButtons">
        <button class="lang-button" type="button" data-group="source" data-lang="auto">자동 감지</button>
        <button class="lang-button" type="button" data-group="source" data-lang="en">🇺🇸 English</button>
        <button class="lang-button" type="button" data-group="source" data-lang="ko">🇰🇷 Korean</button>
        <button class="lang-button" type="button" data-group="source" data-lang="ja">🇯🇵 Japanese</button>
      </div>
    </div>
    <div class="field">
      <label>번역 언어</label>
      <div class="language-row target-row" id="targetButtons">
        <button class="lang-button" type="button" data-group="target" data-lang="ko">🇰🇷 Korean</button>
        <button class="lang-button" type="button" data-group="target" data-lang="en">🇺🇸 English</button>
        <button class="lang-button" type="button" data-group="target" data-lang="ja">🇯🇵 Japanese</button>
      </div>
    </div>
    <div class="status-line" id="requestHint">언어를 선택하면 바로 다시 번역됩니다.</div>
  </div>
  <div class="advice-panel" id="errorAdvice" aria-live="polite"></div>

  <div class="section">
    <div class="source-header">
      <div class="label">원문</div>
      <button class="action-button primary" id="runTranslateButton" type="button">번역 실행</button>
    </div>
    <textarea class="source-input" id="originalText" spellcheck="false"></textarea>
  </div>
  <div class="section">
    <div class="label">번역</div>
    <div class="text-box translated" id="translatedText"></div>
  </div>
  <div class="footer">
    <span class="status" id="statusText">클립보드에 복사됨</span>
    <span class="model">__MODEL_LABEL__</span>
  </div>
  </main>
</div>

<script>
let originalText = __ORIGINAL_JSON__.normalize('NFC');
let translatedText = __TRANSLATED_JSON__.normalize('NFC');
const initialDirection = __DIRECTION_JSON__;
const initialSource = __SOURCE_JSON__;
const initialTarget = __TARGET_JSON__;
const ollamaModel = __MODEL_JSON__;
let historyItems = __HISTORY_JSON__;

const langs = {
  en: { flag: '🇺🇸', name: 'English' },
  ko: { flag: '🇰🇷', name: 'Korean' },
  ja: { flag: '🇯🇵', name: 'Japanese' }
};

let sourceLang = initialSource || 'auto';
let targetLang = initialTarget || 'ko';
let requestId = 0;
let sourceDirty = false;
let historyQuery = '';
let historyPairFilter = 'all';

const directionEl = document.getElementById('directionText');
const originalEl = document.getElementById('originalText');
const translatedEl = document.getElementById('translatedText');
const statusEl = document.getElementById('statusText');
const requestHintEl = document.getElementById('requestHint');
const runTranslateButton = document.getElementById('runTranslateButton');
const languageButtons = Array.from(document.querySelectorAll('.lang-button'));
const historyListEl = document.getElementById('historyList');
const historySearchEl = document.getElementById('historySearch');
const historyFiltersEl = document.getElementById('historyFilters');
const historyCountEl = document.getElementById('historyCount');
const errorAdviceEl = document.getElementById('errorAdvice');

originalEl.value = originalText;
translatedEl.textContent = translatedText;

function detectLanguage(text) {
  const counts = { ko: 0, ja: 0, en: 0 };
  for (const ch of text) {
    const code = ch.charCodeAt(0);
    if (code >= 0xac00 && code <= 0xd7a3) counts.ko += 1;
    else if ((code >= 0x3040 && code <= 0x30ff) || (code >= 0xff66 && code <= 0xff9f)) counts.ja += 1;
    else if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) counts.en += 1;
  }
  if (counts.ko > counts.en && counts.ko >= counts.ja) return 'ko';
  if (counts.ja > 0 && counts.ja >= counts.ko) return 'ja';
  return 'en';
}

function currentOriginal() {
  return originalEl.value.normalize('NFC').trim();
}

function resolvedSource() {
  return sourceLang === 'auto' ? detectLanguage(currentOriginal()) : sourceLang;
}

function updateControls() {
  for (const button of languageButtons) {
    const group = button.dataset.group;
    const lang = button.dataset.lang;
    const active = group === 'source' ? lang === sourceLang : lang === targetLang;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', active ? 'true' : 'false');
  }
  updateDirection();
}

function updateDirection() {
  const source = resolvedSource();
  const target = targetLang;
  directionEl.textContent = `${langs[source].flag} → ${langs[target].flag}`;
}

function setStatus(text, isError = false) {
  statusEl.textContent = text.normalize('NFC');
  statusEl.classList.toggle('error', isError);
}

function setRequestHint(text, isError = false) {
  requestHintEl.textContent = text.normalize('NFC');
  requestHintEl.style.color = isError ? '#d93f3f' : '#6b6f80';
}

function hideAdvice() {
  errorAdviceEl.classList.remove('visible');
  errorAdviceEl.replaceChildren();
}

function showAdvice(title, steps) {
  errorAdviceEl.replaceChildren();
  const titleEl = document.createElement('div');
  titleEl.className = 'advice-title';
  titleEl.textContent = title;
  const list = document.createElement('ol');
  for (const step of steps) {
    const item = document.createElement('li');
    const parts = String(step).split(/(`[^`]+`)/g);
    for (const part of parts) {
      if (part.startsWith('`') && part.endsWith('`')) {
        const code = document.createElement('code');
        code.textContent = part.slice(1, -1);
        item.appendChild(code);
      } else {
        item.appendChild(document.createTextNode(part));
      }
    }
    list.appendChild(item);
  }
  errorAdviceEl.append(titleEl, list);
  errorAdviceEl.classList.add('visible');
}

function friendlyError(error) {
  const message = String(error?.message || '');
  const lower = message.toLowerCase();
  const kind = error?.kind || '';
  if (kind === 'model_missing' || (lower.includes('model') && lower.includes('not found'))) {
    return {
      title: 'Ollama 모델이 설치되어 있지 않습니다.',
      hint: `터미널에서 ollama pull ${ollamaModel} 실행`,
      steps: [
        `터미널에서 \`ollama pull ${ollamaModel}\` 실행`,
        '`lt status`로 Model installed가 ok인지 확인',
        '다시 번역 실행'
      ]
    };
  }
  if (kind === 'ollama_unreachable' || lower.includes('connection refused') || lower.includes('failed to fetch') || lower.includes('couldn')) {
    return {
      title: 'Ollama가 꺼져 있거나 연결되지 않았습니다.',
      hint: 'Ollama 앱을 실행한 뒤 다시 시도',
      steps: [
        'Ollama 앱 실행 또는 터미널에서 `ollama serve` 실행',
        '`lt status`로 Ollama host가 ok인지 확인',
        '다시 번역 실행'
      ]
    };
  }
  if (kind === 'ollama_timeout' || lower.includes('timed out') || lower.includes('timeout')) {
    return {
      title: 'Ollama 응답 시간이 너무 오래 걸렸습니다.',
      hint: '모델 로딩 후 다시 시도하거나 입력을 줄여보세요.',
      steps: [
        '`ollama ps`로 모델이 로딩 중인지 확인',
        '처음 실행 직후라면 잠시 기다렸다가 다시 번역 실행',
        '긴 원문이면 일부만 나눠서 번역'
      ]
    };
  }
  return {
    title: '번역 요청에 실패했습니다.',
    hint: 'lt status와 로그를 확인하세요.',
    steps: [
      '`lt status` 실행',
      '`tail -n 80 /tmp/translategemma_result_server.log` 확인',
      '문제가 계속되면 `lt stop` 후 `lt server` 재실행'
    ]
  };
}

function setBusy(isBusy) {
  for (const button of languageButtons) button.disabled = isBusy;
  runTranslateButton.disabled = isBusy;
  runTranslateButton.textContent = isBusy ? '번역 중' : '번역 실행';
}

function buildPrompt(source, target) {
  return `Translate the source text from ${langs[source].name} (${source}) to ${langs[target].name} (${target}). Output only the ${langs[target].name} translation. Do not include the source text, language labels, markdown, quotes, explanations, alternatives, or multiple versions. Preserve the original tone and meaning.`;
}

function cleanTranslationOutput(text, target) {
  const originalOutput = String(text || '').normalize('NFC').trim();
  const labelMap = {
    ko: ['Korean', '한국어', 'Korea'],
    en: ['English', '영어'],
    ja: ['Japanese', '日本語', '일본어']
  };
  const allLabels = ['Korean', '한국어', 'Korea', 'English', '영어', 'Japanese', '日本語', '일본어'];
  const lines = originalOutput.replaceAll(String.fromCharCode(13), '').split(String.fromCharCode(10));
  const chunks = [];
  let current = null;

  for (const line of lines) {
    const stripped = line.trim().replace(/^\*+|\*+$/g, '').trim();
    const matched = allLabels.find((label) => {
      const lower = label.toLowerCase();
      const value = stripped.toLowerCase();
      return value === lower || value === `${lower}:`;
    });
    if (matched) {
      current = [];
      chunks.push({ label: matched, lines: current });
    } else if (current) {
      current.push(line);
    }
  }

  const targetLabels = labelMap[target] || [];
  const targetChunk = chunks.find((chunk) => targetLabels.some((label) => label.toLowerCase() === chunk.label.toLowerCase()));
  if (targetChunk) {
    const cleaned = targetChunk.lines.join(String.fromCharCode(10)).trim();
    if (cleaned) text = cleaned;
  }

  text = String(text || '').normalize('NFC').trim();
  if (text.length >= 2 && ['"', '“', '”'].includes(text[0]) && ['"', '“', '”'].includes(text[text.length - 1])) {
    text = text.slice(1, -1).trim();
  }
  return text || originalOutput;
}

function langFlag(lang) {
  return langs[lang]?.flag || 'Auto';
}

function compactText(text, maxLength = 92) {
  const value = String(text || '').replaceAll(String.fromCharCode(13), ' ').replaceAll(String.fromCharCode(10), ' ').trim();
  return value.length > maxLength ? `${value.slice(0, maxLength - 1)}…` : value;
}

function historyPair(item) {
  return `${item.source || 'auto'}>${item.target || 'ko'}`;
}

function historyPairLabel(pair) {
  if (pair === 'all') return '전체';
  const parts = pair.split('>');
  return `${langFlag(parts[0])} → ${langFlag(parts[1])}`;
}

function filteredHistoryItems() {
  const query = historyQuery.trim().toLowerCase();
  return historyItems.filter((item) => {
    const pairOk = historyPairFilter === 'all' || historyPair(item) === historyPairFilter;
    if (!pairOk) return false;
    if (!query) return true;
    const haystack = `${item.original || ''} ${item.translated || ''}`.toLowerCase();
    return haystack.includes(query);
  });
}

function renderHistoryFilters() {
  const pairs = Array.from(new Set(historyItems.map(historyPair))).filter(Boolean);
  const filters = ['all', ...pairs];
  if (historyPairFilter !== 'all' && !pairs.includes(historyPairFilter)) historyPairFilter = 'all';
  historyFiltersEl.innerHTML = '';
  for (const pair of filters) {
    const button = document.createElement('button');
    button.className = `history-filter${pair === historyPairFilter ? ' active' : ''}`;
    button.type = 'button';
    button.textContent = historyPairLabel(pair);
    button.addEventListener('click', () => {
      historyPairFilter = pair;
      renderHistory();
    });
    historyFiltersEl.appendChild(button);
  }
}

function renderHistory(activeId = null) {
  renderHistoryFilters();
  const items = filteredHistoryItems();
  historyListEl.innerHTML = '';
  historyCountEl.textContent = `${items.length} / ${historyItems.length}`;
  if (!historyItems.length) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent = '아직 저장된 번역이 없습니다.';
    historyListEl.appendChild(empty);
    return;
  }
  if (!items.length) {
    const empty = document.createElement('div');
    empty.className = 'history-empty';
    empty.textContent = '검색 결과가 없습니다.';
    historyListEl.appendChild(empty);
    return;
  }

  for (const item of items) {
    const button = document.createElement('button');
    button.className = `history-item${item.id === activeId ? ' active' : ''}`;
    button.type = 'button';
    button.dataset.id = item.id;

    const main = document.createElement('div');
    main.className = 'history-main';

    const route = document.createElement('div');
    route.className = 'history-route';
    route.textContent = `${langFlag(item.source)} → ${langFlag(item.target)}`;

    const original = document.createElement('div');
    original.className = 'history-original';
    original.textContent = compactText(item.original, 120);

    const translated = document.createElement('div');
    translated.className = 'history-translated';
    translated.textContent = compactText(item.translated, 120);

    const time = document.createElement('div');
    time.className = 'history-time';
    time.textContent = item.createdAt ? item.createdAt.replace('T', ' ') : '';

    const deleteButton = document.createElement('button');
    deleteButton.className = 'history-delete';
    deleteButton.type = 'button';
    deleteButton.setAttribute('aria-label', '히스토리 삭제');
    deleteButton.textContent = '×';
    deleteButton.addEventListener('click', (event) => {
      event.stopPropagation();
      deleteHistoryItem(item.id);
    });

    main.append(route, original, translated, time);
    button.append(main, deleteButton);
    button.addEventListener('click', () => loadHistoryItem(item.id));
    historyListEl.appendChild(button);
  }
}

function loadHistoryItem(id) {
  const item = historyItems.find((entry) => entry.id === id);
  if (!item) return;
  originalText = String(item.original || '').normalize('NFC');
  translatedText = String(item.translated || '').normalize('NFC');
  sourceLang = item.source || 'auto';
  targetLang = item.target || 'ko';
  originalEl.value = originalText;
  translatedEl.textContent = translatedText;
  sourceDirty = false;
  updateControls();
  setStatus('히스토리에서 불러왔습니다.');
  setRequestHint('필요하면 수정 후 번역 실행을 누르세요.');
  renderHistory(id);
}

async function saveHistoryItem(item) {
  historyItems = [item, ...historyItems.filter((entry) => entry.id !== item.id)].slice(0, 50);
  renderHistory(item.id);
  try {
    const response = await fetch('/history', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(item)
    });
    if (response.ok) {
      const data = await response.json();
      if (Array.isArray(data.history)) {
        historyItems = data.history;
        renderHistory(item.id);
      }
    }
  } catch {}
}

async function syncHistoryFromServer(activeId = null) {
  try {
    const response = await fetch('/history');
    if (!response.ok) return;
    const data = await response.json();
    if (Array.isArray(data.history)) {
      historyItems = data.history;
      renderHistory(activeId);
    }
  } catch {}
}

async function deleteHistoryItem(id) {
  historyItems = historyItems.filter((entry) => entry.id !== id);
  renderHistory(null);
  try {
    const response = await fetch('/history/delete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id })
    });
    if (response.ok) {
      const data = await response.json();
      if (Array.isArray(data.history)) {
        historyItems = data.history;
        renderHistory(null);
      }
    }
    setStatus('히스토리에서 삭제했습니다.');
  } catch {}
}

async function copyText(text) {
  try {
    const response = await fetch('/copy', {
      method: 'POST',
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: text
    });
    if (!response.ok) throw new Error('server clipboard copy failed');
    setStatus('클립보드에 복사됨');
    return;
  } catch {
    try {
      await navigator.clipboard.writeText(text);
      setStatus('클립보드에 복사됨');
      return;
    } catch {
      setStatus('번역 완료. 브라우저 권한 때문에 자동 복사는 생략됐습니다.');
    }
  }
}

async function translateCurrentSelection() {
  originalText = currentOriginal();
  const source = resolvedSource();
  const target = targetLang;
  const currentRequest = ++requestId;

  updateControls();
  if (!originalText) {
    setStatus('원문을 입력하세요.', true);
    setRequestHint('번역할 텍스트가 비어 있습니다.', true);
    return;
  }
  if (source === target) {
    setStatus('원문 언어와 번역 언어가 같습니다.', true);
    setRequestHint('다른 번역 언어를 선택하세요.', true);
    return;
  }

  setBusy(true);
  setStatus('번역 중...');
  setRequestHint(`${langs[source].name} → ${langs[target].name}`);
  hideAdvice();

  const payload = {
    model: ollamaModel,
    stream: false,
    options: {
      temperature: 0.2,
      top_p: 0.85,
      top_k: 40,
      repeat_penalty: 1.05,
      seed: 42,
      num_ctx: 8192
    },
    messages: [
      {
        role: 'system',
        content: 'You are a translation engine. Return exactly one translation in the requested target language and nothing else. Never include the source text, language labels, markdown headings, quotes around the whole answer, explanations, alternatives, or multiple language versions.'
      },
      {
        role: 'user',
        content: `${buildPrompt(source, target)}\n\n${originalText}`
      }
    ]
  };

  try {
    const response = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await response.json().catch(() => ({ error: 'Invalid translator server response', kind: 'server_response' }));
    if (currentRequest !== requestId) return;
    if (!response.ok || data.error || !data.message || !data.message.content) {
      const requestError = new Error(data.error || 'Unexpected Ollama response');
      requestError.kind = data.kind || '';
      throw requestError;
    }
    translatedText = cleanTranslationOutput(data.message.content, target) || data.message.content.trim().normalize('NFC');
    translatedEl.textContent = translatedText;
    sourceDirty = false;
    const historyItem = {
      id: String(Date.now()),
      createdAt: new Date().toISOString().slice(0, 19),
      source,
      target,
      direction: `${langs[source].flag} → ${langs[target].flag}`,
      original: originalText,
      translated: translatedText
    };
    await saveHistoryItem(historyItem);
    setRequestHint('완료');
    hideAdvice();
    await copyText(translatedText);
  } catch (error) {
    if (currentRequest === requestId) {
      const friendly = friendlyError(error);
      setStatus(friendly.title, true);
      setRequestHint(friendly.hint, true);
      showAdvice(friendly.title, friendly.steps);
    }
  } finally {
    if (currentRequest === requestId) setBusy(false);
  }
}

for (const button of languageButtons) {
  button.addEventListener('click', () => {
    const group = button.dataset.group;
    const lang = button.dataset.lang;
    if (group === 'source') {
      if (sourceLang === lang) return;
      sourceLang = lang;
    } else {
      if (targetLang === lang) return;
      targetLang = lang;
    }
    translateCurrentSelection();
  });
}

originalEl.addEventListener('input', () => {
  sourceDirty = true;
  updateDirection();
  setStatus('원문이 수정되었습니다.');
  setRequestHint('Command + Enter 또는 번역 실행으로 번역합니다.');
  hideAdvice();
});

originalEl.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    translateCurrentSelection();
  }
});

historySearchEl.addEventListener('input', () => {
  historyQuery = historySearchEl.value;
  renderHistory();
});

runTranslateButton.addEventListener('click', translateCurrentSelection);

renderHistory(historyItems[0]?.id || null);
syncHistoryFromServer(historyItems[0]?.id || null);
updateControls();
</script>
</body>
</html>'''

html = html.replace('__ORIGINAL_JSON__', original_json)
html = html.replace('__TRANSLATED_JSON__', translated_json)
html = html.replace('__DIRECTION_JSON__', direction_json)
html = html.replace('__SOURCE_JSON__', source_json)
html = html.replace('__TARGET_JSON__', target_json)
html = html.replace('__MODEL_JSON__', model_json)
html = html.replace('__MODEL_LABEL__', model_label)
html = html.replace('__HISTORY_JSON__', history_json)

with open('/tmp/translation_result.html', 'w', encoding='utf-8') as f:
    f.write(html)
PYEOF

if [ -s /tmp/translategemma_result_server.pid ]; then
  OLD_PID=$(cat /tmp/translategemma_result_server.pid)
  if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null
    sleep 0.2
    if kill -0 "$OLD_PID" 2>/dev/null; then
      kill -9 "$OLD_PID" 2>/dev/null
    fi
  fi
fi
rm -f /tmp/translategemma_result_url.txt /tmp/translategemma_result_server.pid
python3 - <<'PYEOF' >/tmp/translategemma_result_server.log 2>&1 &
import http.server
import json
import os
import subprocess
import socket
import urllib.error
import urllib.request
from pathlib import Path

HOST = '127.0.0.1'
RESULT_PORT = int(os.environ.get('LT_RESULT_PORT', '57575'))
HTML_PATH = Path('/tmp/translation_result.html')
URL_PATH = Path('/tmp/translategemma_result_url.txt')
PID_PATH = Path('/tmp/translategemma_result_server.pid')
HISTORY_PATH = Path('/tmp/translategemma_history.json')
OLLAMA_HOST = os.environ.get('OLLAMA_HOST', 'http://127.0.0.1:11434').rstrip('/')



def load_history():
    try:
        data = json.loads(HISTORY_PATH.read_text(encoding='utf-8'))
        return data if isinstance(data, list) else []
    except Exception:
        return []

def save_history(history):
    HISTORY_PATH.write_text(json.dumps(history[:50], ensure_ascii=False), encoding='utf-8')

def error_payload(kind, message, detail=''):
    payload = {'kind': kind, 'error': message}
    if detail:
        payload['detail'] = detail
    return json.dumps(payload, ensure_ascii=False)

def classify_ollama_http_error(exc):
    raw = exc.read().decode('utf-8', errors='replace')
    message = raw.strip() or str(exc)
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict) and parsed.get('error'):
            message = str(parsed['error'])
    except Exception:
        pass
    lower = message.lower()
    if exc.code == 404 and 'model' in lower and ('not found' in lower or 'try pulling' in lower or 'pull' in lower):
        return 'model_missing', message
    return 'ollama_http_error', message

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print('%s - - [%s] %s' % (self.address_string(), self.log_date_time_string(), fmt % args), flush=True)

    def _send(self, status, body, content_type='text/plain; charset=utf-8'):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ('/', '/translation_result.html'):
            self._send(200, HTML_PATH.read_bytes(), 'text/html; charset=utf-8')
        elif self.path == '/history':
            payload = json.dumps({'history': load_history()}, ensure_ascii=False)
            self._send(200, payload, 'application/json; charset=utf-8')
        elif self.path == '/favicon.ico':
            self._send(204, b'')
        else:
            self._send(404, 'Not found')

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        if self.path == '/api/chat':
            req = urllib.request.Request(
                OLLAMA_HOST + '/api/chat',
                data=body,
                headers={'Content-Type': 'application/json'},
                method='POST',
            )
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    self._send(resp.status, resp.read(), resp.headers.get('Content-Type', 'application/json'))
            except urllib.error.HTTPError as exc:
                kind, message = classify_ollama_http_error(exc)
                status = 404 if kind == 'model_missing' else 502
                self._send(status, error_payload(kind, message), 'application/json; charset=utf-8')
            except (urllib.error.URLError, ConnectionRefusedError) as exc:
                detail = str(getattr(exc, 'reason', exc))
                kind = 'ollama_timeout' if 'timed out' in detail.lower() else 'ollama_unreachable'
                message = f'Could not reach Ollama at {OLLAMA_HOST}'
                self._send(502, error_payload(kind, message, detail), 'application/json; charset=utf-8')
            except (TimeoutError, socket.timeout) as exc:
                self._send(504, error_payload('ollama_timeout', 'Ollama request timed out', str(exc)), 'application/json; charset=utf-8')
            except Exception as exc:
                self._send(502, error_payload('translator_server_error', str(exc)), 'application/json; charset=utf-8')
        elif self.path == '/copy':
            try:
                subprocess.run(['pbcopy'], input=body, check=True)
                self._send(200, 'ok')
            except Exception as exc:
                self._send(500, str(exc))
        elif self.path == '/history':
            try:
                item = json.loads(body.decode('utf-8'))
                history = load_history()
                history = [entry for entry in history if entry.get('id') != item.get('id')]
                history.insert(0, item)
                history = history[:50]
                save_history(history)
                payload = json.dumps({'history': history}, ensure_ascii=False)
                self._send(200, payload, 'application/json; charset=utf-8')
            except Exception as exc:
                self._send(500, str(exc))
        elif self.path == '/history/delete':
            try:
                payload_in = json.loads(body.decode('utf-8'))
                item_id = payload_in.get('id')
                history = [entry for entry in load_history() if entry.get('id') != item_id]
                save_history(history)
                payload = json.dumps({'history': history}, ensure_ascii=False)
                self._send(200, payload, 'application/json; charset=utf-8')
            except Exception as exc:
                self._send(500, str(exc))
        else:
            self._send(404, 'Not found')

server = http.server.ThreadingHTTPServer((HOST, RESULT_PORT), Handler)
URL_PATH.write_text(f'http://{HOST}:{RESULT_PORT}/translation_result.html', encoding='utf-8')
PID_PATH.write_text(str(os.getpid()), encoding='utf-8')

server.serve_forever()
PYEOF

for i in {1..50}; do
  if [ -s /tmp/translategemma_result_url.txt ]; then
    break
  fi
  sleep 0.1
done

if [ ! -s /tmp/translategemma_result_url.txt ]; then
  printf '%s\n' "Failed to start result server. See /tmp/translategemma_result_server.log" >&2
  tail -n 20 /tmp/translategemma_result_server.log >&2 2>/dev/null || true
  exit 1
fi

RESULT_URL=$(cat /tmp/translategemma_result_url.txt)
printf '%s\n' "Result URL: $RESULT_URL"
open "$RESULT_URL"
