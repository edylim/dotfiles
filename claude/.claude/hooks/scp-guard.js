#!/usr/bin/env node
// PreToolUse hook (Bash) — workflow rule: don't scp/rsync source files to another server;
// the repo exists there, so sync via git (commit -> push -> pull). Forces an explicit
// approval prompt ("ask") rather than hard-blocking, since occasional scp is legitimate.
const { readHookInput, emit } = require("./lib.js");

try {
  const input = readHookInput();
  const cmd = String((input.tool_input && input.tool_input.command) || "");
  if (!cmd) emit(null);

  // Match scp or rsync invocations that reference a remote target ([user@]host:path).
  const isTransfer = /\b(scp|rsync)\b/.test(cmd);
  const hasRemote = /(^|\s)([\w.-]+@)?[\w.-]+:[^\s]/.test(cmd);
  if (!(isTransfer && hasRemote)) emit(null);

  emit({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason:
        "This looks like scp/rsync of files to another host. Per the git workflow rule: don't push source files over scp — the same repo almost certainly exists on the remote. Sync code via git instead (commit → push, then pull on the remote). Approve only if this is genuinely a non-repo file (data, artifact, secret-free asset) that can't go through git.",
    },
  });
} catch {
  emit(null);
}
