#!/usr/bin/env node
// UserPromptSubmit hook — mitigates failure mode #5 (sycophancy on idea evaluation).
// When the user asks for an opinion/evaluation, inject a reminder to respond as a
// critical reviewer rather than agreeing reflexively. Additive context only; never blocks.
const { readHookInput, emit } = require("./lib.js");

try {
  const input = readHookInput();
  const prompt = String(input.prompt || "");

  const EVAL_PATTERNS = [
    /\bwhat do you think\b/i,
    /\bshould i\b/i,
    /\bis (this|that|it)\b[^.?!]*\b(a )?(good|bad|right|correct|sensible|reasonable)\b/i,
    /\b(good|bad|terrible|great) (idea|approach|design|plan|call)\b/i,
    /\bthoughts\??/i,
    /\bdoes (this|that|it) make sense\b/i,
    /\bam i (right|wrong)\b/i,
    /\bdo you (agree|think)\b/i,
    /\bfeedback on\b/i,
    /\breview (my|this|the)\b/i,
    /\bis (this|that|my)\b[^.?!]*\b(right|correct|ok|okay|fine|sound)\b/i,
    /\bsound(s)? good\b/i,
    /\b(critique|evaluate|assess|sanity[- ]check)\b/i,
    /\bright\?\s*$/i,
  ];

  const isEval = EVAL_PATTERNS.some((re) => re.test(prompt));
  if (!isEval) emit(null);

  emit({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "ANTI-SYCOPHANCY (the user is asking you to evaluate something): Respond as a critical, independent reviewer — NOT a cheerleader. Lead with the strongest objections, risks, and failure modes. State disagreement plainly and early. Do not open with praise, do not soften with flattery, and do not agree reflexively. Judge the idea on its merits regardless of whose idea it is or which answer they seem to want. If it is genuinely good, say so briefly and say why; if it is flawed, say so directly and propose the better alternative.",
    },
  });
} catch {
  emit(null);
}
