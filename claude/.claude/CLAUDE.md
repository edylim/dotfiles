# Global Rules

## #1 Rule: NEVER GUESS

When something doesn't work, STOP. Research the correct fix — WebSearch, WebFetch, read docs, read source code, check GitHub issues. Do NOT chain speculative fixes. If you're about to say "this should work" without verifying, that's guessing. Go verify first.

- Use Agent tool (subagent_type=Explore) for deep codebase research
- Use background agents for long-running investigation
- Diagnose ROOT CAUSE before attempting any fix
- One correct fix > five attempted workarounds
- If you don't know, USE YOUR TOOLS to find out — never tell the user to "go check" something

## Code

- Read before editing. Study surrounding code for patterns, then match them.
- Prefer editing existing files over creating new ones
- Readability over cleverness. Small focused functions. Meaningful names.
- Verify work: run tests/linters before claiming done

## Communication

- Concise and direct. Explain complex changes, skip obvious ones.
- Ask before large refactors
- No speculative filler ("likely", "probably") when you haven't verified

## Git

- Never add Co-Authored-By or AI attribution
- Atomic commits, "why" not "what" in messages
- Rebase over merge. Fixup noise.
- Never commit secrets

## Safety

- Review before destructive operations
- NEVER use `sleep` in foreground Bash — use `run_in_background`
