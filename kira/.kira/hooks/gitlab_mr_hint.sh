#!/bin/bash
# UserPromptSubmit hook: when the user's message contains a gitlab.com merge-request
# URL, inject the EXACT command to fetch it — with the URL verbatim. Deterministic
# fix for two weak-talker failures: (a) it reformulates the URL into a raw api/v4
# path and drops the namespace group (-> 404), and (b) it doesn't reliably load the
# gitlab skill. This puts the right command + the unmangled URL straight into context
# every turn it's relevant, so the talker just relays it instead of improvising.
# Reads stdin FIRST (python3 - <<heredoc would eat it), then regexes the raw JSON.
input=$(cat)
python3 -c '
import sys, re, json
raw = sys.argv[1] if sys.argv[1:] else ""
m = re.search(r"https?://gitlab\.com/[^\s\"]*?/-/merge_requests/\d+", raw)
if not m:
    sys.exit(0)
url = m.group(0)
q = chr(39)  # a literal single quote here would close the bash single-quoted -c block
cmd = "kira-b70 -e MR_URL=" + repr(url) + " -c " + q + "from anima.tools.gl import fetch_mr; fetch_mr()" + q
ctx = (
    "GITLAB MR DETECTED (" + url + "). To fetch it, delegate ONE thread to run "
    "EXACTLY this, VERBATIM, as a shell command — kira-b70 is a local CLI wrapper "
    "(it already does the SSH + docker-exec), so do NOT prefix it with `ssh`, do "
    "NOT add `2>&1` or `| head` (the sandbox blocks redirection), do NOT rewrite "
    "the URL into an api/v4 path, do NOT drop any part of the namespace, and do "
    "NOT use curl/WebFetch/urllib or invent a token:\n    " + cmd + "\n"
    "For the diff instead of metadata, add: -e MODE=changes . The gl logic lives "
    "in the container (anima.tools.gl); it reads the gitlab token there and parses "
    "the URL itself."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": ctx}}))
' "$input"
