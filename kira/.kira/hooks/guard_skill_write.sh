#!/bin/bash
# PreToolUse hook: stop Kira from hand-authoring a NEW skill file. Skills must go
# through the CreateSkill tool, which guarantees the dir-form path
# (~/.kira/skills/<name>/SKILL.md) and the YAML frontmatter.
#
# Covers two routes (matcher in settings.json = Write|Edit|Bash):
#   - Write/Edit: deny when file_path is under /skills/ and doesn't exist yet.
#   - Bash:       deny when the command WRITES to a skills SKILL path (redirect /
#                 tee / cp / mv / install / dd) — the workaround a model reaches
#                 for after a Write deny. NOTE: a soft nudge, not a sandbox —
#                 printf / python -c open() etc. can still slip through; the goal
#                 is to steer toward CreateSkill, not to seal every path.
# Edits to EXISTING skill files pass through (only new hand-authoring is redirected).
# Input: JSON on stdin with tool_name + tool_input. Deny via permissionDecision.
# NOTE: capture stdin into a var first — a python heredoc would otherwise eat it.
input=$(cat)
python3 -c '
import sys, json, os, re
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)  # never block on a parse error
tool = d.get("tool_name") or ""
ti = d.get("tool_input") or {}

DENY = (
    "Do not hand-write skill files (not with Write/Edit, and not with Bash "
    "redirects/echo/printf/cp either). Use the CreateSkill tool - pass name, "
    "description, and body; it writes the correct <name>/SKILL.md path with "
    "proper YAML frontmatter and loads it immediately."
)
def deny():
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": DENY,
    }}))
    sys.exit(0)

if tool in ("Write", "Edit"):
    fp = ti.get("file_path") or ""
    if "/skills/" in fp and not os.path.exists(fp):
        deny()
elif tool == "Bash":
    cmd = ti.get("command") or ""
    # A write operator (redirect / tee / cp / mv / install / dd) whose target is a
    # skills SKILL path. The [^|;&\n]* keeps the operator and the path in the same
    # simple command, so "cat skills/x/SKILL.md 2>/dev/null" (a read) is NOT caught.
    if re.search(r"(>>?|\btee\b|\bcp\b|\bmv\b|\binstall\b|\bdd\b)[^|;&\n]*skills/[^|;&\n]*SKILL", cmd):
        deny()
' "$input"
