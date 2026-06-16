#!/usr/bin/env node
// Stop hook — failure mode #3 (claiming TESTS PASS without running them).
// Blocks finishing ONLY when, in the recent working window, a CODE file was edited and the
// final message claims the tests pass, but no test runner was executed after that edit.
//
// Precision guards (learned from a real false positive where meta-discussion of this very
// hook tripped it):
//   - Only CODE-file edits arm the gate (editing .md/.json/docs does not).
//   - Only edits since the last couple of REAL user turns count (an edit hours ago can't
//     arm the gate for the rest of the session). tool_result entries are NOT user turns.
//   - Claim patterns are narrowed to genuine "tests pass" assertions, not general
//     "verified it works" prose (which matches discussion about testing).
//
// Safety (this is the only hook that can force continuation, so loops are the risk):
//   - Honors `stop_hook_active` (standard loop-guard).
//   - Fires AT MOST ONCE per session via a state marker.
//   - Fails open on any error.
const fs = require("fs");
const path = require("path");
const { readHookInput, readTranscript, toolUses, lastAssistantText, emit } = require("./lib.js");

const STATE_DIR = path.join(__dirname, ".state");

// Narrowed to genuine test-pass claims (NOT general "verified/works" prose).
const CLAIM_PATTERNS = [
  /\b(all\s+|the\s+)?tests?\s+(now\s+)?(pass|passing|are\s+passing|succeed|green)\b/i,
  /\btest\s+suite\b[^.?!]*\b(pass|passing|green)\b/i,
  /\btests?\s*[:\-]?\s*(✓|✅)/i,
];

const TEST_RUNNER =
  /\b(pytest|py\.test|jest|vitest|mocha|jasmine|rspec|phpunit|tox|nose2?|ctest)\b|\bgo\s+test\b|\bcargo\s+test\b|\bgradle\b[^&|]*\btest\b|\bmvn\b[^&|]*\btest\b|\bdotnet\s+test\b|\brake\s+([^&|]*\s)?test\b|\b(npm|yarn|pnpm|bun)\s+(run\s+)?test\b|\bmake\s+([^&|]*\s)?test\b/i;

// Only edits to actual source files arm the gate.
const CODE_FILE =
  /\.(py|js|mjs|cjs|jsx|ts|tsx|go|rs|rb|java|kt|kts|swift|c|cc|cpp|cxx|h|hpp|cs|php|scala|ex|exs|sh|bash|zsh|lua|vue|svelte|m|mm|dart|clj|hs|ml|sql)$/i;

const EDIT_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);

try {
  const input = readHookInput();
  if (input.stop_hook_active === true) emit(null);

  const sessionId = String(input.session_id || "unknown").replace(/[^\w.-]/g, "_");
  const marker = path.join(STATE_DIR, `verify-${sessionId}`);
  if (fs.existsSync(marker)) emit(null);

  const transcript = readTranscript(input.transcript_path);
  if (!transcript.length) emit(null);

  // Recency cutoff: index of the 2nd-to-last REAL user prompt (tool_result carriers don't count).
  const userIdxs = [];
  transcript.forEach((e, i) => {
    if (e.type !== "user") return;
    const c = e.message && e.message.content;
    const isToolResult = Array.isArray(c) && c.some((b) => b && b.type === "tool_result");
    if (!isToolResult) userIdxs.push(i);
  });
  const cutoff = userIdxs.length >= 2 ? userIdxs[userIdxs.length - 2] : userIdxs.length ? userIdxs[0] : -1;

  const uses = toolUses(transcript);
  const recentCodeEdits = uses.filter(
    (u) => EDIT_TOOLS.has(u.name) && u.idx >= cutoff && CODE_FILE.test(String(u.input.file_path || ""))
  );
  if (!recentCodeEdits.length) emit(null); // no recent code edit → nothing to verify

  const lastCodeEdit = recentCodeEdits[recentCodeEdits.length - 1];
  const ranTestAfter = uses.some(
    (u) => u.idx > lastCodeEdit.idx && u.name === "Bash" && TEST_RUNNER.test(String(u.input.command || ""))
  );
  if (ranTestAfter) emit(null); // tests actually ran after the edit → fine

  const finalText = lastAssistantText(transcript);
  if (!CLAIM_PATTERNS.some((re) => re.test(finalText))) emit(null); // no test-pass claim

  try {
    fs.writeFileSync(marker, String(Date.now()));
  } catch {
    /* accept slight loop risk; stop_hook_active catches the next iteration */
  }

  emit({
    decision: "block",
    reason:
      "You claimed the tests pass, but you edited code and did NOT run a test command afterward. Per rule #3 (verify before claiming done): actually run the tests now and report the real result. If there are no tests to run or you cannot run them, say so explicitly instead of claiming they pass.",
  });
} catch {
  emit(null);
}
