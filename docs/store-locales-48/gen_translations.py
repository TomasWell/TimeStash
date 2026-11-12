#!/usr/bin/env python3
"""TimeStash 商店页 28 个新 locale 的文案生成（复用 MiniMax 翻译管线模式）。

来源：A 区 [app:TimeStash] 任务（48 locale 扩展）。
母版：master.json（从 ASC 实拉 en-US / zh-Hans）。
产物：translations.json —— {locale: {name, subtitle, description, keywords, promotionalText}}
"""
import json, os, re, sys, time, urllib.request

AUTH_PATH = os.path.expanduser("~/.hermes/auth.json")
API_URL = "https://api.minimaxi.com/anthropic/v1/messages"
MODEL = "MiniMax-M3.1-Flash"
HERE = os.path.dirname(os.path.abspath(__file__))

# 28 个缺失 locale（基准=FreeLedger 全量 48，TimeStash 现有 20）
LOCALES = ["ar-SA","bn-BD","ca","de-DE","en-AU","en-CA","en-GB","es-ES","fr-FR","gu-IN",
           "kn-IN","ml-IN","mr-IN","nl-NL","no","or-IN","pa-IN","ru","sk","sl-SI",
           "ta-IN","te-IN","th","tr","uk","ur-PK","vi","zh-Hant"]

LANG_NAMES = {
    "ar-SA":"Arabic (Saudi Arabia)","bn-BD":"Bengali (Bangladesh)","ca":"Catalan",
    "de-DE":"German (Germany)","en-AU":"English (Australia)","en-CA":"English (Canada)",
    "en-GB":"English (United Kingdom)","es-ES":"Spanish (Spain)","fr-FR":"French (France)",
    "gu-IN":"Gujarati (India)","kn-IN":"Kannada","ml-IN":"Malayalam","mr-IN":"Marathi",
    "nl-NL":"Dutch (Netherlands)","no":"Norwegian","or-IN":"Oriya (India)","pa-IN":"Punjabi",
    "ru":"Russian","sk":"Slovak","sl-SI":"Slovenian","ta-IN":"Tamil","te-IN":"Telugu",
    "th":"Thai","tr":"Turkish","uk":"Ukrainian","ur-PK":"Urdu (Pakistan)","vi":"Vietnamese",
    "zh-Hant":"Chinese Traditional",
}

def get_token():
    auth = json.load(open(AUTH_PATH, encoding="utf-8"))
    for entry in auth.get("credential_pool", {}).get("minimax-cn", []):
        for field in ("access_token", "api_key", "key"):
            if entry.get(field):
                return entry[field]
    raise SystemExit("no minimax cred")

def call_llm(prompt, max_tokens=16000, retries=4):
    token = get_token()
    for attempt in range(retries):
        try:
            body = {"model": MODEL, "max_tokens": max_tokens,
                    "messages": [{"role": "user", "content": prompt}]}
            req = urllib.request.Request(API_URL, data=json.dumps(body).encode("utf-8"),
                headers={"content-type":"application/json","x-api-key":token,
                         "anthropic-version":"2023-06-01"})
            with urllib.request.urlopen(req, timeout=240) as resp:
                d = json.loads(resp.read().decode())
            for blk in d.get("content", []):
                if blk.get("type") == "text":
                    return blk["text"]
            last = "no text block"
        except Exception as e:
            last = str(e)[:200]
        time.sleep(3 * (attempt + 1))
    return None

def main():
    master = json.load(open(os.path.join(HERE, "master.json"), encoding="utf-8"))
    en, zh = master["en-US"], master["zh-Hans"]
    out_path = os.path.join(HERE, "translations.json")
    out = json.load(open(out_path, encoding="utf-8")) if os.path.exists(out_path) else {}
    for loc in LOCALES:
        if loc in out:
            print(f"[skip] {loc} 已有"); continue
        prompt = f"""You are a professional App Store localization expert. Translate app store listing copy from English (with Chinese reference) into {LANG_NAMES[loc]}.

STRICT RULES:
1. Brand name "TimeStash" must stay EXACTLY as "TimeStash" (do not translate/transliterate).
2. Output ONLY valid JSON with these keys: name, subtitle, description, keywords, promotionalText. No markdown fences, no commentary.
3. name = "TimeStash" for all locales, EXCEPT: zh-Hant uses "時間收納箱"; en-AU/en-CA/en-GB use "TimeStash: Save Time" (must match device display name).
4. subtitle: max 30 characters.
5. keywords: comma-separated single words/phrases, total length (excluding commas) must be <= 100 chars, no spaces after commas.
6. description: keep the exact structure with 【】section markers and bullet "•" markers and line breaks.
7. promotionalText: 1-2 sentences, max 170 chars.
8. Do NOT add absolute privacy claims (no "completely offline", no "no internet"). The privacy section says: data stays on device; no automatic network requests; the only network use is links the user taps; no account needed, nothing uploaded. Translate this section faithfully.
9. Use natural native {LANG_NAMES[loc]} as used in that App Store territory.

ENGLISH SOURCE:
name: TimeStash: Save Time
subtitle: {en['subtitle']}
keywords: {en['keywords']}
promotionalText: {en['promotionalText']}
description:
{en['description']}

CHINESE REFERENCE (for meaning):
{zh['description']}"""
        # master.json 里 subtitle/promotionalText 可能在 appInfo 层 —— 从 en attributes 补
        txt = call_llm(prompt)
        if not txt:
            print(f"[FAIL] {loc}: LLM no response"); continue
        m = re.search(r'\{.*\}', txt, re.S)
        if not m:
            print(f"[FAIL] {loc}: no JSON"); continue
        try:
            d = json.loads(m.group(0))
        except json.JSONDecodeError:
            print(f"[FAIL] {loc}: bad JSON"); continue
        # 校验
        errs = []
        if "TimeStash" not in str(d.get("name","")) and loc != "zh-Hant":
            errs.append("brand")
        if len(str(d.get("subtitle",""))) > 30: errs.append("subtitle>30")
        kw = str(d.get("keywords",""))
        kwlen = len(kw.replace(",",""))
        if kwlen > 100: errs.append(f"kw>100:{kwlen}")
        if len(str(d.get("description",""))) < 300: errs.append("desc too short")
        if len(str(d.get("promotionalText",""))) > 170: errs.append("promo>170")
        if errs:
            print(f"[RETRY] {loc}: {errs}"); continue
        out[loc] = d
        json.dump(out, open(out_path,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
        print(f"[OK] {loc}")
    print(f"\n共 {len(out)}/{len(LOCALES)} 个 locale 生成完毕")

if __name__ == "__main__":
    main()
