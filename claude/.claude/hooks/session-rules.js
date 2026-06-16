#!/usr/bin/env node
// SessionStart hook — failure mode #10 (compaction/resume amnesia).
// Re-states the core discipline at session start and resume so it is present before
// the first turn even on a resumed/compacted session. Context only; never blocks.
process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext:
        "CORE DISCIPLINE (re-stated at session start): 1) NEVER GUESS — research with WebSearch/WebFetch/Read before asserting; do not chain speculative fixes. 2) VERIFY-OR-LABEL every factual claim (cite a source/file:line/command output, or prefix 'unverified:'). 3) VERIFY BEFORE DONE — actually run tests/build before claiming they pass. 4) Never weaken or delete tests to make them pass. 5) When asked to evaluate an idea, be a critical reviewer, not a cheerleader.",
    },
  })
);
