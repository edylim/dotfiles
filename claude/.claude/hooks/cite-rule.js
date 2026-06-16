#!/usr/bin/env node
// UserPromptSubmit hook — failure mode #2 (confident wrong claims). Always-on.
// Injected every turn so it also survives context compaction (failure mode #10).
process.stdout.write(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "VERIFY-OR-LABEL: Any claim about an API, library, framework, OS/platform behavior, pricing, version, or config flag must carry a citation — a URL you fetched, a file:line you read, or output of a command you ran — OR be explicitly prefixed 'unverified:'. A bare, confident factual assertion with neither is a rule violation. If you are not certain, use WebSearch / WebFetch / Read to verify BEFORE stating it, not after being challenged.",
    },
  })
);
