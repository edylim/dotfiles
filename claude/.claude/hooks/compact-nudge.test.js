#!/usr/bin/env node
// Tests for compact-nudge.js and the gauge statusline.py leaves for it.
// Plain node, no deps:  node claude/.claude/hooks/compact-nudge.test.js
// The status line half runs under every interpreter in STATUSLINE_PYTHONS (space-separated,
// default "python3"); the mac runs /usr/bin/python3 3.9, so include a 3.9 when you have one.
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const HOOK = path.join(__dirname, "compact-nudge.js");
const STATUSLINE = path.join(__dirname, "..", "statusline.py");
const PYTHONS = (process.env.STATUSLINE_PYTHONS || "python3").split(/\s+/).filter(Boolean);

const SID_A = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa";
const SID_B = "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb";
const POINT = 686000;

const TEXT_85_90 =
  "At the next clean boundary, checkpoint everything critical to ~/.ai-memory (decisions, live state, in-flight work), " +
  'then tell Ed: "good /compact point — everything is banked". Only Ed can run /compact.';
const TEXT_95 = "Auto-compact is close: checkpoint to memory NOW, before any further large reads, then ask Ed to /compact.";

function tmpCache() {
  const xdg = fs.mkdtempSync(path.join(os.tmpdir(), "compact-nudge-test-"));
  const ctx = path.join(xdg, "claude-statusline", "ctx");
  fs.mkdirSync(ctx, { recursive: true });
  return { xdg, ctx, cleanup: () => fs.rmSync(xdg, { recursive: true, force: true }) };
}

// What statusline.py writes; `over` replaces fields (undefined deletes one).
function seed(ctx, sid, frac, over = {}) {
  const g = { session_id: sid, frac, used: Math.round(frac * POINT), point: POINT, window: 1000000, ts: Date.now() / 1000, ...over };
  for (const k of Object.keys(g)) if (g[k] === undefined) delete g[k];
  fs.writeFileSync(path.join(ctx, `${sid}.json`), JSON.stringify(g));
}

function runHook(xdg, input) {
  const stdin = typeof input === "string" ? input : JSON.stringify(input);
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, env: { ...process.env, XDG_CACHE_HOME: xdg }, encoding: "utf8" });
  assert.equal(r.status, 0, `hook exit ${r.status}, stderr: ${r.stderr}`);
  assert.equal(r.stderr, "", "hook wrote to stderr");
  if (!r.stdout) return null;
  const out = JSON.parse(r.stdout); // anything printed must be JSON
  return out;
}

function nudge(out, event) {
  assert.ok(out, `expected a nudge on ${event}, got silence`);
  assert.deepEqual(Object.keys(out), ["hookSpecificOutput"]);
  assert.equal(out.hookSpecificOutput.hookEventName, event);
  return out.hookSpecificOutput.additionalContext;
}

const ptu = (sid, extra = {}) => ({ hook_event_name: "PostToolUse", session_id: sid, tool_name: "Bash", ...extra });
const ups = (sid, extra = {}) => ({ hook_event_name: "UserPromptSubmit", session_id: sid, prompt: "hi", ...extra });

// ---- the hook ---------------------------------------------------------------------------

test("exact text: 85/90% and 95%, with the numbers", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.9);
    assert.equal(
      nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit"),
      `[compact-nudge] Context is at 90% of the auto-compact point (~617k of 686k tokens). ${TEXT_85_90}`
    );
    seed(c.ctx, SID_A, 0.96);
    assert.equal(
      nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit"),
      `[compact-nudge] Context is at 96% of the auto-compact point (~659k of 686k tokens). ${TEXT_95}`
    );
  } finally {
    c.cleanup();
  }
});

test("subagent (agent_id) is silent on both events and leaves no state", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.96);
    assert.equal(runHook(c.xdg, ptu(SID_A, { agent_id: "agent-123", agent_type: "general-purpose" })), null);
    assert.equal(runHook(c.xdg, ups(SID_A, { agent_id: "agent-123" })), null);
    assert.ok(!fs.existsSync(path.join(c.ctx, `${SID_A}.nudge.json`)));
    // --agent main thread (agent_type without agent_id) still gets it
    nudge(runHook(c.xdg, ptu(SID_A, { agent_type: "reviewer" })), "PostToolUse");
  } finally {
    c.cleanup();
  }
});

test("no gauge file is silent", () => {
  const c = tmpCache();
  try {
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    assert.equal(runHook(c.xdg, ups(SID_A)), null);
    fs.rmSync(c.ctx, { recursive: true }); // not even the ctx dir
    assert.equal(runHook(c.xdg, ups(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

test("stale gauge (> 10 min) is silent; just under 10 min is not", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.9, { ts: Date.now() / 1000 - 601 });
    assert.equal(runHook(c.xdg, ups(SID_A)), null);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    seed(c.ctx, SID_A, 0.9, { ts: Date.now() / 1000 - 590 });
    nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit");
  } finally {
    c.cleanup();
  }
});

test("a stale gauge below 50% does not reset the bands", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.9);
    nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse");
    seed(c.ctx, SID_A, 0.1, { ts: Date.now() / 1000 - 3600 });
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    seed(c.ctx, SID_A, 0.9);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null, "band 90 was already sent");
  } finally {
    c.cleanup();
  }
});

test("malformed gauge files are silent", () => {
  const c = tmpCache();
  const file = path.join(c.ctx, `${SID_A}.json`);
  try {
    for (const body of ["", "{", "null", "[]", "42", '"x"']) {
      fs.writeFileSync(file, body);
      assert.equal(runHook(c.xdg, ups(SID_A)), null, `body ${JSON.stringify(body)}`);
    }
    const bad = [
      { frac: "0.9" },
      { frac: null },
      { frac: -1 },
      { ts: undefined },
      { ts: "now" },
      { used: undefined },
      { point: undefined },
      { point: 0 },
      { session_id: SID_B }, // someone else's gauge under this name
    ];
    for (const over of bad) {
      seed(c.ctx, SID_A, 0.9, over);
      assert.equal(runHook(c.xdg, ups(SID_A)), null, `override ${JSON.stringify(over)}`);
      assert.equal(runHook(c.xdg, ptu(SID_A)), null, `override ${JSON.stringify(over)}`);
    }
    fs.rmSync(file);
    fs.mkdirSync(file); // a directory where the file should be
    assert.equal(runHook(c.xdg, ups(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

test("malformed or unexpected stdin is silent", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.96);
    const inputs = [
      "",
      "not json",
      "{",
      "null",
      "[]",
      "42",
      JSON.stringify({ session_id: SID_A }), // no event
      JSON.stringify({ hook_event_name: "Stop", session_id: SID_A }),
      JSON.stringify({ hook_event_name: "PreToolUse", session_id: SID_A }),
      JSON.stringify({ hook_event_name: "PostToolUse" }), // no session
      JSON.stringify({ hook_event_name: "PostToolUse", session_id: 7 }),
      JSON.stringify({ hook_event_name: "PostToolUse", session_id: "" }),
      JSON.stringify({ hook_event_name: "PostToolUse", session_id: `../ctx/${SID_A}` }),
      JSON.stringify({ hook_event_name: "PostToolUse", session_id: `${SID_A}/x` }),
      JSON.stringify({ hook_event_name: "PostToolUse", session_id: `.${SID_A}` }),
    ];
    for (const s of inputs) assert.equal(runHook(c.xdg, s), null, `stdin ${s}`);
  } finally {
    c.cleanup();
  }
});

test("below 85% is silent; 85% exactly is not", () => {
  const c = tmpCache();
  try {
    for (const f of [0, 0.3, 0.5, 0.84, 0.8499]) {
      seed(c.ctx, SID_A, f);
      assert.equal(runHook(c.xdg, ups(SID_A)), null, `frac ${f}`);
      assert.equal(runHook(c.xdg, ptu(SID_A)), null, `frac ${f}`);
    }
    seed(c.ctx, SID_A, 0.85);
    assert.match(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"), /at 85% of/);
  } finally {
    c.cleanup();
  }
});

test("PostToolUse: each band once, on entering it", () => {
  const c = tmpCache();
  try {
    const seq = [
      [0.86, "at 86%"],
      [0.87, null],
      [0.88, null],
      [0.91, "at 91%"],
      [0.93, null],
      [0.96, "at 96%"],
      [0.98, null],
      [1.0, null],
    ];
    for (const [f, want] of seq) {
      seed(c.ctx, SID_A, f);
      const out = runHook(c.xdg, ptu(SID_A));
      if (want) assert.ok(nudge(out, "PostToolUse").includes(want), `frac ${f}`);
      else assert.equal(out, null, `frac ${f}`);
    }
  } finally {
    c.cleanup();
  }
});

test("PostToolUse: jumping straight to 95% sends the 95% text once, and a lower band after it is silent", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.97);
    assert.ok(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse").endsWith(TEXT_95));
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    seed(c.ctx, SID_A, 0.9);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

test("UserPromptSubmit: every prompt from 85%, and the same turn's tool calls don't repeat its band", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.87);
    for (let i = 0; i < 3; i++) assert.match(nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit"), /at 87%/);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null, "band 85 already sent by the prompt");
    seed(c.ctx, SID_A, 0.91);
    assert.match(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"), /at 91%/);
    assert.match(nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit"), /at 91%/);
    // a prompt at a lower band never lowers the recorded band
    seed(c.ctx, SID_A, 0.86);
    nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit");
    seed(c.ctx, SID_A, 0.92);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

test("below 50% (a compaction) resets the bands; 50% exactly does not", () => {
  const c = tmpCache();
  const state = path.join(c.ctx, `${SID_A}.nudge.json`);
  try {
    seed(c.ctx, SID_A, 0.96);
    nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse");
    seed(c.ctx, SID_A, 0.5);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    assert.ok(fs.existsSync(state), "50% is not a reset");
    seed(c.ctx, SID_A, 0.96);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);

    seed(c.ctx, SID_A, 0.12);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    assert.ok(!fs.existsSync(state), "below 50% clears the state");
    seed(c.ctx, SID_A, 0.6);
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    seed(c.ctx, SID_A, 0.86);
    assert.match(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"), /at 86%/);
    seed(c.ctx, SID_A, 0.9);
    assert.match(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"), /at 90%/);
    // UserPromptSubmit resets too
    seed(c.ctx, SID_A, 0.2);
    assert.equal(runHook(c.xdg, ups(SID_A)), null);
    assert.ok(!fs.existsSync(state));
  } finally {
    c.cleanup();
  }
});

test("a malformed band state file counts as nothing sent", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.9);
    fs.writeFileSync(path.join(c.ctx, `${SID_A}.nudge.json`), "{garbage");
    nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse");
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

test("concurrent sessions don't cross", () => {
  const c = tmpCache();
  try {
    seed(c.ctx, SID_A, 0.9);
    seed(c.ctx, SID_B, 0.3);
    assert.match(nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"), /at 90%/);
    assert.equal(runHook(c.xdg, ptu(SID_B)), null);
    assert.equal(runHook(c.xdg, ups(SID_B)), null);
    seed(c.ctx, SID_B, 0.91);
    assert.match(nudge(runHook(c.xdg, ptu(SID_B)), "PostToolUse"), /at 91%/, "A's band state is not B's");
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    seed(c.ctx, SID_B, 0.1); // B compacts: A's state survives
    runHook(c.xdg, ptu(SID_B));
    assert.ok(fs.existsSync(path.join(c.ctx, `${SID_A}.nudge.json`)));
    assert.ok(!fs.existsSync(path.join(c.ctx, `${SID_B}.nudge.json`)));
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
  } finally {
    c.cleanup();
  }
});

function runHookAsync(xdg, input) {
  return new Promise((resolve) => {
    const p = spawn(process.execPath, [HOOK], { env: { ...process.env, XDG_CACHE_HOME: xdg } });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("close", (code) => resolve({ code, out }));
    p.stdin.end(JSON.stringify(input));
  });
}

// Without the lock, a round of 12 duplicated in ~30% of rounds here (9/30), so run enough
// rounds that a missing lock can't pass by luck.
test("parallel tool calls crossing a band send one nudge, not one each", async () => {
  const c = tmpCache();
  const state = path.join(c.ctx, `${SID_A}.nudge.json`);
  try {
    for (let round = 0; round < 10; round++) {
      fs.rmSync(state, { force: true });
      for (const f of [0.9, 0.96]) {
        seed(c.ctx, SID_A, f);
        const rs = await Promise.all(Array.from({ length: 12 }, () => runHookAsync(c.xdg, ptu(SID_A))));
        assert.ok(rs.every((r) => r.code === 0));
        const sent = rs.filter((r) => r.out);
        assert.equal(sent.length, 1, `round ${round}, frac ${f}: ${sent.length} nudges`);
        assert.ok(!fs.existsSync(`${state}.lock`), "lock released");
      }
    }
  } finally {
    c.cleanup();
  }
});

test("lock: a live holder means silence; a dead holder's lock is taken over", () => {
  const c = tmpCache();
  const lock = path.join(c.ctx, `${SID_A}.nudge.json.lock`);
  try {
    seed(c.ctx, SID_A, 0.9);
    fs.writeFileSync(lock, "");
    assert.equal(runHook(c.xdg, ptu(SID_A)), null);
    const old = Date.now() / 1000 - 30;
    fs.utimesSync(lock, old, old);
    nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse");
    assert.ok(!fs.existsSync(lock));
    // UserPromptSubmit never waits on the lock
    fs.writeFileSync(lock, "");
    nudge(runHook(c.xdg, ups(SID_A)), "UserPromptSubmit");
  } finally {
    c.cleanup();
  }
});

test("latency: median under 60 ms, silent and nudging, with a 1 MB tool_response", () => {
  const c = tmpCache();
  try {
    const big = ptu(SID_A, { tool_input: { command: "cat big" }, tool_response: { stdout: "x".repeat(1 << 20) } });
    const time = (input, n = 15) => {
      const ms = [];
      for (let i = 0; i < n; i++) {
        const t = process.hrtime.bigint();
        runHook(c.xdg, input);
        ms.push(Number(process.hrtime.bigint() - t) / 1e6);
      }
      ms.sort((a, b) => a - b);
      return ms[Math.floor(n / 2)];
    };
    seed(c.ctx, SID_A, 0.3);
    const silent = time(ptu(SID_A));
    const silentBig = time(big);
    seed(c.ctx, SID_A, 0.9);
    const nudging = time(ups(SID_A));
    console.log(`# hook latency medians: silent ${silent.toFixed(1)} ms, silent+1MB ${silentBig.toFixed(1)} ms, nudging ${nudging.toFixed(1)} ms`);
    for (const m of [silent, silentBig, nudging]) assert.ok(m < 60, `${m.toFixed(1)} ms`);
  } finally {
    c.cleanup();
  }
});

// ---- statusline.py's side ------------------------------------------------------------------

function statuslineEnv(xdg) {
  const cache = path.join(xdg, "claude-statusline");
  fs.mkdirSync(cache, { recursive: true });
  // fresh refresh markers, so a render never spawns the background usage/ledger refresh
  for (const m of ["usage.json.tried", "ledger.json.tried", "spawned"]) fs.writeFileSync(path.join(cache, m), "");
  const conf = path.join(xdg, "claude-config"); // no settings.json: only the env below counts
  fs.mkdirSync(conf, { recursive: true });
  const env = { ...process.env, XDG_CACHE_HOME: xdg, CLAUDE_CONFIG_DIR: conf, CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: "70", COLUMNS: "120" };
  for (const v of ["DISABLE_AUTO_COMPACT", "DISABLE_COMPACT", "CLAUDE_CODE_AUTO_COMPACT_WINDOW"]) delete env[v];
  return env;
}

function render(py, xdg, stdin, args = []) {
  const r = spawnSync(py, [STATUSLINE, ...args], { input: JSON.stringify(stdin), env: statuslineEnv(xdg), encoding: "utf8", cwd: xdg });
  assert.equal(r.status, 0, r.stderr);
  return r;
}

const renderInput = (sid, used, extra = {}) => ({
  session_id: sid,
  workspace: { current_dir: os.tmpdir() },
  context_window: { context_window_size: 1000000, current_usage: { input_tokens: 10, cache_creation_input_tokens: 90, cache_read_input_tokens: used - 100 } },
  ...extra,
});

for (const py of PYTHONS) {
  const version = spawnSync(py, ["--version"], { encoding: "utf8" });
  const label = `[${(version.stdout || version.stderr || py).trim()}]`;

  test(`${label} statusline writes the session's gauge, atomically`, () => {
    const c = tmpCache();
    try {
      const before = Date.now() / 1000;
      render(py, c.xdg, renderInput(SID_A, 617400));
      const g = JSON.parse(fs.readFileSync(path.join(c.ctx, `${SID_A}.json`), "utf8"));
      assert.deepEqual(Object.keys(g).sort(), ["frac", "point", "session_id", "ts", "used", "window"]);
      assert.equal(g.session_id, SID_A);
      assert.equal(g.point, 686000); // 1M window, PCT 70: (1M - 20k) * 0.7
      assert.equal(g.window, 1000000);
      assert.equal(g.used, 617400);
      assert.equal(g.frac, 0.9);
      assert.ok(g.ts >= before - 1 && g.ts <= Date.now() / 1000 + 1);
      assert.deepEqual(fs.readdirSync(c.ctx).filter((f) => f.includes(".tmp")), [], "no temp files left");
    } finally {
      c.cleanup();
    }
  });

  test(`${label} statusline: the gauge caps at 1.0; used_percentage after a /compact; an empty context is 0`, () => {
    const c = tmpCache();
    const read = () => JSON.parse(fs.readFileSync(path.join(c.ctx, `${SID_A}.json`), "utf8"));
    try {
      render(py, c.xdg, renderInput(SID_A, 700000));
      assert.equal(read().frac, 1);
      render(py, c.xdg, { session_id: SID_A, context_window: { context_window_size: 1000000, current_usage: null, used_percentage: 3 } });
      assert.equal(read().used, 30000);
      render(py, c.xdg, { session_id: SID_A, context_window: { context_window_size: 1000000, current_usage: null } });
      assert.equal(read().frac, 0);
      assert.equal(read().point, 686000);
    } finally {
      c.cleanup();
    }
  });

  test(`${label} statusline writes nothing without a usable session id or a window`, () => {
    const c = tmpCache();
    try {
      render(py, c.xdg, renderInput(undefined, 617400));
      render(py, c.xdg, renderInput(42, 617400));
      render(py, c.xdg, renderInput("", 617400));
      render(py, c.xdg, renderInput("../escaped", 617400));
      render(py, c.xdg, renderInput(`${SID_A}/x`, 617400));
      render(py, c.xdg, { session_id: SID_A }); // no context_window: nothing measured
      render(py, c.xdg, "not an object");
      assert.deepEqual(fs.readdirSync(c.ctx), []);
      assert.ok(!fs.existsSync(path.join(c.xdg, "claude-statusline", "escaped.json")));
    } finally {
      c.cleanup();
    }
  });

  test(`${label} statusline --refresh prunes gauge and nudge files older than a week, and only those`, () => {
    const c = tmpCache();
    try {
      const old = Date.now() / 1000 - 8 * 86400;
      const files = { [`${SID_A}.json`]: old, [`${SID_A}.nudge.json`]: old, [`${SID_A}.nudge.json.lock`]: old, [`${SID_B}.json`]: null, [`${SID_B}.nudge.json`]: null };
      for (const [f, t] of Object.entries(files)) {
        fs.writeFileSync(path.join(c.ctx, f), "{}");
        if (t) fs.utimesSync(path.join(c.ctx, f), t, t);
      }
      spawnSync(py, [STATUSLINE, "--refresh"], { env: statuslineEnv(c.xdg), encoding: "utf8" });
      assert.deepEqual(fs.readdirSync(c.ctx).sort(), [`${SID_B}.json`, `${SID_B}.nudge.json`]);
      assert.ok(fs.existsSync(path.join(c.xdg, "claude-statusline", "ctx-prune.tried")));
      // and not again within a day
      fs.writeFileSync(path.join(c.ctx, "later.json"), "{}");
      fs.utimesSync(path.join(c.ctx, "later.json"), old, old);
      spawnSync(py, [STATUSLINE, "--refresh"], { env: statuslineEnv(c.xdg), encoding: "utf8" });
      assert.ok(fs.existsSync(path.join(c.ctx, "later.json")));
    } finally {
      c.cleanup();
    }
  });

  test(`${label} round trip: a render at 90% makes the hook nudge with its numbers`, () => {
    const c = tmpCache();
    try {
      render(py, c.xdg, renderInput(SID_A, 617400));
      assert.equal(
        nudge(runHook(c.xdg, ptu(SID_A)), "PostToolUse"),
        `[compact-nudge] Context is at 90% of the auto-compact point (~617k of 686k tokens). ${TEXT_85_90}`
      );
      render(py, c.xdg, renderInput(SID_A, 100000)); // compacted
      assert.equal(runHook(c.xdg, ptu(SID_A)), null);
      assert.ok(!fs.existsSync(path.join(c.ctx, `${SID_A}.nudge.json`)));
    } finally {
      c.cleanup();
    }
  });
}
