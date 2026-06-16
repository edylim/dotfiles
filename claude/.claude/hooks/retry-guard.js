#!/usr/bin/env node
// PostToolUse hook (Bash) — failure mode #4 (trial-and-error / chaining speculative fixes).
// If the SAME command has been run repeatedly, the model is likely flailing. Inject a
// reminder to stop guessing and research the root cause. Additive context only; never blocks.
const { readHookInput, readTranscript, toolUses, emit } = require("./lib.js");

const THRESHOLD = 3; // run count (including current) that triggers the nudge
const WINDOW = 25; // only look at the most recent N bash commands

function normalize(cmd) {
  return String(cmd || "")
    .replace(/\s+/g, " ")
    .trim();
}

try {
  const input = readHookInput();
  const current = normalize(input.tool_input && input.tool_input.command);
  if (!current) emit(null);

  const transcript = readTranscript(input.transcript_path);
  const bashCmds = toolUses(transcript)
    .filter((u) => u.name === "Bash")
    .map((u) => normalize(u.input.command));

  // The current command may or may not already be in the transcript depending on
  // flush timing; count matches in the recent window and ensure the current is counted.
  // PostToolUse fires after the result is recorded, so the current command is already
  // in the transcript — counting occurrences there is authoritative.
  const recent = bashCmds.slice(-WINDOW);
  const count = recent.filter((c) => c === current).length;

  if (count < THRESHOLD) emit(null);

  emit({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext:
        `RETRY LOOP DETECTED: you have run this command ${count} times. Per rule #1 (NEVER GUESS): stop re-running variations. If it keeps failing, the cause is not the invocation — diagnose the ROOT CAUSE. Read the failing source/config, read the docs, or WebSearch the exact error before the next attempt. Do not chain another speculative fix.`,
    },
  });
} catch {
  emit(null);
}
