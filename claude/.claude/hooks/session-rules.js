#!/usr/bin/env node
// SessionStart hook — failure mode #10 (compaction/resume amnesia).
// Re-states the core discipline at session start and resume so it is present before
// the first turn even on a resumed/compacted session. Context only; never blocks.
const os = require("os");
const boxHost = os.hostname(); // "kira" on the box
// The machine Ed launched from. Set by the client shim (KIRA_CLAUDE_ORIGIN); falls back
// to the ssh client, then to the box itself (e.g. a kira-studio term-pane launch).
const KNOWN_HOSTS = { "192.168.20.125": "balthazar (Ed's mac)", "192.168.20.130": boxHost };
const sshIp = process.env.SSH_CLIENT ? String(process.env.SSH_CLIENT).split(" ")[0] : "";
const origin =
  process.env.KIRA_CLAUDE_ORIGIN ||
  (sshIp ? KNOWN_HOSTS[sshIp] || `the calling machine (${sshIp})` : boxHost);
const thisBox =
  origin === boxHost
    ? "the kira box you are running on"
    : `${origin} — reach it over ssh; it is NOT the box you are running on`;
process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext:
        "CORE DISCIPLINE (re-stated at session start): 1) NEVER GUESS — research with WebSearch/WebFetch/Read before asserting; do not chain speculative fixes. 2) VERIFY-OR-LABEL every factual claim (cite a source/file:line/command output, or prefix 'unverified:'). 3) VERIFY BEFORE DONE — actually run tests/build before claiming they pass. 4) Never weaken or delete tests to make them pass. 5) When asked to evaluate an idea, be a critical reviewer, not a cheerleader.\n\n" +
        `HOST & ORIGIN: You are Claude Code running ON the kira box (host "${boxHost}", 192.168.20.130) — the single Claude surface. Your shell, cwd, files, and tools all act on the kira box, not on whatever machine Ed is sitting at. This session was launched from: ${origin}. When Ed says "this box", "this machine", or "here", he means ${thisBox}.`,
    },
  })
);
