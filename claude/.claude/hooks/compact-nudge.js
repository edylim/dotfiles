#!/usr/bin/env node
// PostToolUse + UserPromptSubmit hook: warn the MAIN-THREAD model before auto-compact fires.
// Neither the model nor a hook can run /compact, so this says how close it is; the model
// checkpoints to ~/.ai-memory at a clean boundary and asks Ed to /compact by hand.
//
// The numbers come from statusline.py, which leaves its ctx gauge (fraction of the
// auto-compact point) in <cache>/ctx/<session_id>.json on every render.
//   UserPromptSubmit  every prompt from 85%
//   PostToolUse       once per band (85 / 90 / 95%), on entering a band higher than the last
//                     one sent; <session_id>.nudge.json remembers it, and a gauge below 50%
//                     (a compaction happened) clears it.
// Silent on everything else: subagents, no or stale (> 10 min) gauge, below 85%, any error.
// Additive context only; never blocks, never exits non-zero.
const fs = require("fs");
const os = require("os");
const path = require("path");
const { readHookInput, emit } = require("./lib.js");

const BANDS = [95, 90, 85]; // percent of the auto-compact point, highest first
const RESET_BELOW = 0.5;
const STALE_S = 600;
const LOCK_STALE_MS = 5000;
const SESSION_ID = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/; // statusline.py's SESSION_ID

// statusline.py: $XDG_CACHE_HOME or ~/.cache, + claude-statusline/ctx
function ctxDir() {
  const base = process.env.XDG_CACHE_HOME || path.join(process.env.HOME || os.homedir(), ".cache");
  return path.join(base, "claude-statusline", "ctx");
}

function finite(x) {
  return typeof x === "number" && Number.isFinite(x);
}

// The session's gauge, or null when it is missing, malformed, someone else's, or stale.
function readGauge(dir, sid) {
  let g;
  try {
    g = JSON.parse(fs.readFileSync(path.join(dir, sid + ".json"), "utf8"));
  } catch {
    return null;
  }
  if (!g || g.session_id !== sid) return null;
  if (!finite(g.frac) || g.frac < 0 || !finite(g.used) || !finite(g.point) || !finite(g.ts)) return null;
  if (Date.now() / 1000 - g.ts > STALE_S) return null;
  return g;
}

function bandOf(frac) {
  return BANDS.find((b) => frac * 100 >= b) || 0;
}

function lastBand(statePath) {
  try {
    const s = JSON.parse(fs.readFileSync(statePath, "utf8"));
    return finite(s.band) ? s.band : 0;
  } catch {
    return 0;
  }
}

function saveBand(statePath, band) {
  const tmp = `${statePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ band, ts: Date.now() / 1000 }));
  fs.renameSync(tmp, statePath);
}

// PostToolUse fires once per tool, concurrently for parallel tool calls; the lock keeps a
// batch that crosses a band to one nudge. A holder that died leaves a lock that is taken
// over after LOCK_STALE_MS.
function tryLock(lockPath) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      fs.closeSync(fs.openSync(lockPath, "wx"));
      return true;
    } catch (e) {
      if (!e || e.code !== "EEXIST") return false;
      try {
        if (Date.now() - fs.statSync(lockPath).mtimeMs < LOCK_STALE_MS) return false;
        fs.unlinkSync(lockPath);
      } catch {
        return false;
      }
    }
  }
  return false;
}

function message(g, band) {
  const k = (n) => `${Math.round(n / 1000)}k`;
  const head =
    `[compact-nudge] Context is at ${Math.round(g.frac * 100)}% of the auto-compact point ` +
    `(~${k(g.used)} of ${k(g.point)} tokens). `;
  if (band >= 95) {
    return head + "Auto-compact is close: checkpoint to memory NOW, before any further large reads, then ask Ed to /compact.";
  }
  return (
    head +
    "At the next clean boundary, checkpoint everything critical to ~/.ai-memory (decisions, live state, in-flight work), " +
    'then tell Ed: "good /compact point — everything is banked". Only Ed can run /compact.'
  );
}

try {
  const input = readHookInput();
  const event = input.hook_event_name;
  if (event !== "PostToolUse" && event !== "UserPromptSubmit") emit(null);
  if (input.agent_id) emit(null); // inside a subagent: the nudge is for the main thread
  const sid = input.session_id;
  if (typeof sid !== "string" || !SESSION_ID.test(sid)) emit(null);

  const dir = ctxDir();
  const gauge = readGauge(dir, sid);
  if (!gauge) emit(null);

  const statePath = path.join(dir, `${sid}.nudge.json`);
  if (gauge.frac < RESET_BELOW) {
    try {
      fs.unlinkSync(statePath);
    } catch {
      /* nothing sent yet */
    }
    emit(null);
  }
  const band = bandOf(gauge.frac);
  if (!band || !(gauge.point > 0)) emit(null);

  if (event === "PostToolUse") {
    const lockPath = `${statePath}.lock`;
    if (!tryLock(lockPath)) emit(null); // a parallel call holds it and sends this band
    let entering = false;
    try {
      entering = band > lastBand(statePath);
      if (entering) saveBand(statePath, band);
    } finally {
      try {
        fs.unlinkSync(lockPath);
      } catch {
        /* already gone */
      }
    }
    if (!entering) emit(null);
  } else {
    // Every prompt gets it. Record the band too, so the same turn's tool calls don't repeat it.
    try {
      if (band > lastBand(statePath)) saveBand(statePath, band);
    } catch {
      /* the nudge still goes out */
    }
  }

  emit({ hookSpecificOutput: { hookEventName: event, additionalContext: message(gauge, band) } });
} catch {
  emit(null);
}
