#!/bin/bash
# PreToolUse hook: stop Kira from hand-authoring a NEW skill file with Write/Edit.
# Skills must go through the CreateSkill tool, which guarantees the dir-form path
# (~/.kira/skills/<name>/SKILL.md) and the YAML frontmatter. Edits to EXISTING
# skill files pass through (only new hand-authoring is redirected).
# Input: JSON on stdin with tool_name + tool_input. Deny via permissionDecision.
# NOTE: capture stdin into a var first — a python heredoc would otherwise eat it.
input=$(cat)
python3 -c '
import sys, json, os
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)  # never block on a parse error
ti = d.get("tool_input") or {}
fp = ti.get("file_path") or ""
if "/skills/" in fp and not os.path.exists(fp):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Do not hand-write skill files. Use the CreateSkill tool instead - "
                "pass name, description, and body; it writes the correct "
                "<name>/SKILL.md path with proper YAML frontmatter and loads it."
            ),
        }
    }))
' "$input"
