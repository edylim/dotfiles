#!/bin/bash
# PostToolUse hook: fast syntax check on code Kira just wrote/edited, so breakage
# is caught immediately and fed back instead of relying on her to remember to
# verify. Only checks what's fast + reliable per-file (py, js); other types pass.
# Feedback via hookSpecificOutput.additionalContext. NOTE: capture stdin first —
# a python heredoc would eat it.
input=$(cat)
python3 -c '
import sys, json, os, subprocess
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)
fp = (d.get("tool_input") or {}).get("file_path") or ""
if not fp or not os.path.exists(fp):
    sys.exit(0)
ext = os.path.splitext(fp)[1].lower()
if ext == ".py":
    cmd = ["python3", "-m", "py_compile", fp]
elif ext in (".js", ".mjs", ".cjs"):
    cmd = ["node", "--check", fp]
else:
    sys.exit(0)  # only the checks that are fast + reliable without project config
try:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
except Exception:
    sys.exit(0)
if r.returncode != 0:
    err = (r.stderr or r.stdout or "").strip()[:600]
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": f"Syntax check FAILED for {os.path.basename(fp)} right after your edit:\n{err}\nFix this before moving on.",
    }}))
' "$input"
