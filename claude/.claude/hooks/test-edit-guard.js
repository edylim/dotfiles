#!/usr/bin/env node
// PreToolUse hook (Edit|Write|MultiEdit|NotebookEdit) — failure mode #9 (reward hacking).
// Editing a test file is a classic way to "make tests pass" by changing the tests
// instead of fixing the code. This does NOT hard-block — it forces an explicit human
// approval prompt ("ask"), so legitimate test changes still go through, deliberately.
const { readHookInput, emit } = require("./lib.js");

try {
  const input = readHookInput();
  const fp = String((input.tool_input && input.tool_input.file_path) || "");
  if (!fp) emit(null);

  const TEST_PATTERNS = [
    /(^|\/)(tests?|__tests__|specs?)\//i, // tests/, spec/, __tests__/ directories
    /(^|\/)test_[^/]+\.[a-z0-9]+$/i, // test_foo.py
    /[._-]test\.[a-z0-9]+$/i, // foo.test.js, foo_test.go
    /[._-]spec\.[a-z0-9]+$/i, // foo.spec.ts, foo_spec.rb
    /(^|\/)conftest\.py$/i, // pytest conftest
    /Test[A-Z0-9][^/]*\.(java|kt|cs|swift|scala)$/, // FooTest.java, TestFoo.kt
    /(^|\/)[^/]*Tests?\.(swift|cs)$/, // FooTests.swift
  ];

  const isTest = TEST_PATTERNS.some((re) => re.test(fp));
  if (!isTest) emit(null);

  emit({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason:
        `Editing a test file (${fp}). This requires explicit approval as a guard against reward-hacking — making failing tests pass by weakening or deleting the test instead of fixing the code under test. Approve ONLY if this change genuinely belongs in the test (new coverage, fixing a wrong assertion the user agreed is wrong). If you reached for this because the code under test is failing, fix the code instead.`,
    },
  });
} catch {
  emit(null);
}
