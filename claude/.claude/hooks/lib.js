// Shared helpers for Claude Code behavior-enforcement hooks.
// Every hook FAILS OPEN: on any error it must exit 0 with no decision,
// so a buggy hook can never wedge a session.
const fs = require("fs");

function readStdin() {
  try {
    return fs.readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

function readHookInput() {
  try {
    return JSON.parse(readStdin() || "{}");
  } catch {
    return {};
  }
}

// Parse a Claude Code transcript JSONL into an ordered array of entries.
function readTranscript(path) {
  if (!path) return [];
  let raw;
  try {
    raw = fs.readFileSync(path, "utf8");
  } catch {
    return [];
  }
  const out = [];
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    try {
      out.push(JSON.parse(t));
    } catch {
      /* skip malformed line */
    }
  }
  return out;
}

// Flatten assistant tool_use blocks in order: {name, input, idx}.
function toolUses(transcript) {
  const uses = [];
  transcript.forEach((entry, idx) => {
    if (entry.type !== "assistant") return;
    const content = entry.message && entry.message.content;
    if (!Array.isArray(content)) return;
    for (const block of content) {
      if (block && block.type === "tool_use") {
        uses.push({ name: block.name, input: block.input || {}, idx });
      }
    }
  });
  return uses;
}

// Text of the final assistant message (concatenated text blocks).
function lastAssistantText(transcript) {
  for (let i = transcript.length - 1; i >= 0; i--) {
    const entry = transcript[i];
    if (entry.type !== "assistant") continue;
    const content = entry.message && entry.message.content;
    if (!Array.isArray(content)) continue;
    const texts = content
      .filter((b) => b && b.type === "text" && typeof b.text === "string")
      .map((b) => b.text);
    if (texts.length) return texts.join("\n");
  }
  return "";
}

function emit(obj) {
  if (obj) process.stdout.write(JSON.stringify(obj));
  process.exit(0);
}

module.exports = {
  readHookInput,
  readTranscript,
  toolUses,
  lastAssistantText,
  emit,
};
