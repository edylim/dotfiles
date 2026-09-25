#!/usr/bin/env python3
"""Claude Code status line = kiracode's footer, plus the session data Claude Code passes.

kiracode's footer (harness/components/{CtxGauge,StatusFooter,UsageReport}.tsx) is
reproduced string-for-string: the ctx gauge right-aligned on the first row, a blank
row, the session | weekly limit bars, "extra usage spent" | the Fable bar under the
weekly bar, a blank row, then the USAGE ledger box (This month / YTD). The first row's
left side carries what Claude Code adds: user@host, dir, branch, model, effort, cost,
duration, lines changed, cache hit rate and friends.

Data:
  stdin      Claude Code's JSON (https://code.claude.com/docs/en/statusline): model,
             effort, context_window, cost, rate_limits.five_hour/seven_day, ...
  usage API  GET /api/oauth/usage, like kiracode's useUtilization.ts: the Fable weekly
             limit (limits[] kind "weekly_scoped") and spend.used, which stdin lacks.
  ledger     every transcript under ~/.claude/projects + ~/.kira/projects, counted and
             priced like kiracode's usageAggregator.ts: Opus and Fable only, one turn
             per API response (a transcript writes a line per content block), each
             at its own model version's rate, UTC month + YTD.

The two slow sources refresh in a detached background process (usage every 5 min,
ledger every 30 s, as kiracode polls) into ~/.cache/claude-statusline; rendering only
reads those files, so it never waits on the network or a transcript scan. The OAuth
token is read (Keychain on macOS, ~/.claude/.credentials.json elsewhere), never
refreshed, never written, and never put on a command line.

Width: Claude Code sets COLUMNS and pads the status row 2 columns each side (the
footer Box is paddingX={2}), so rows are laid out for COLUMNS - 4.

Runs on the box (python 3.14) and the mac (/usr/bin/python3 3.9): stdlib only.
"""

import json
import re
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "claude-statusline")
USAGE = os.path.join(CACHE, "usage.json")
LEDGER = os.path.join(CACHE, "ledger.json")
LEDGER_FILES = os.path.join(CACHE, "ledger-files.json")
USAGE_TTL = 300  # kiracode polls /api/oauth/usage every 5 min (useUtilization.ts)
LEDGER_TTL = 30  # kiracode refreshes the ledger every 30 s (StatusFooter.tsx)
# v2: responses counted once and priced per model version. Bumped so v1 caches,
# which summed every line of a response, are rebuilt instead of mixed in.
LEDGER_FORMAT = 2

# ---- kiracode's palette ------------------------------------------------------------


def rgb(h):
    return "\033[38;2;%d;%d;%dm" % (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))


R, DIM, BOLD = "\033[0m", "\033[2m", "\033[1m"
C_CTX = rgb("#6aa9ff")  # CtxGauge.tsx
C_SESSION = rgb("#ffb703")  # StatusFooter.tsx
C_WEEKLY = rgb("#c08cff")
C_FABLE = rgb("#5fd7a7")
C_CREDIT = rgb("#8a8a8a")
C_ADD = rgb("#3fb950")  # GitHub's diff green / red, for lines added / removed
C_DEL = rgb("#f85149")
KIRA_ICE = rgb("#afd7ff")  # constants/brand.ts, the USAGE box border
C_USER = "\033[1m" + rgb("#5fd787")
C_DIR = "\033[1m" + rgb("#6aa9ff")
SEP = DIM + "  │  " + R
BLANK = "\u2800"  # braille blank: one empty cell that no trim() removes

# kiracode constants/pricing.ts: USD per 1M tokens, per model version, from
# https://platform.claude.com/docs/en/about-claude/pricing (fetched 2026-09-25).
# (input, output, cache read, 5m cache write, 1h cache write)
_OPUS_4_5_TO_5 = (5, 25, 0.5, 6.25, 10)
_OPUS_4_AND_4_1 = (15, 75, 1.5, 18.75, 30)
PRICING = {
    "claude-fable-5-1": (10, 50, 0.25, 12.5, 20),
    "claude-fable-5": (10, 50, 1, 12.5, 20),
    "claude-opus-5-5": (4, 20, 0.2, 5, 8),
    "claude-opus-5": _OPUS_4_5_TO_5,
    "claude-opus-4-8": _OPUS_4_5_TO_5,
    "claude-opus-4-7": _OPUS_4_5_TO_5,
    "claude-opus-4-6": _OPUS_4_5_TO_5,
    "claude-opus-4-5": _OPUS_4_5_TO_5,
    "claude-opus-4-1": _OPUS_4_AND_4_1,
    "claude-opus-4": _OPUS_4_AND_4_1,
}
# A version the page doesn't list yet is priced at its family's newest documented
# rate. That is an assumption, not a published price: add the row when it ships.
FAMILY_FALLBACK = {"opus": "claude-opus-5-5", "fable": "claude-fable-5-1"}


def family(model):
    return "opus" if model.startswith("claude-opus-") else "fable" if model.startswith("claude-fable-") else None


def rate_for(model):
    """The rate for one model version; a dated id (claude-opus-4-1-20250805) matches its base."""
    if len(model) > 9 and model[-9] == "-" and model[-8:].isdigit():
        model = model[:-9]
    return PRICING.get(model) or PRICING[FAMILY_FALLBACK[family(model)]]


def jround(x):
    """JS Math.round for non-negative numbers (half up, not banker's)."""
    return int(x + 0.5)


# ---- the pieces kiracode draws --------------------------------------------------------


def bar_gauge(label, frac, color, width=12, suffix="", label_pad=0):
    """BarGauge / CtxGauge: 'label: ▰▰▱▱ NN%suffix'."""
    f = max(0, min(width, jround(frac * width)))
    out = DIM + ("%s: " % label).ljust(label_pad) + R
    out += color + "▰" * f + R + DIM + "▱" * (width - f) + R
    out += color + " %s%%" % str(jround(frac * 100)).rjust(3) + R
    if suffix:
        out += DIM + suffix + R
    return out


def gauge_w(label, width, suffix="", label_pad=0):
    return max(len(label) + 2, label_pad) + width + 5 + len(suffix)


# ---- where auto-compact fires -----------------------------------------------------------
# The ctx gauge reads against the auto-compact point, not the whole window (Ed, 09-25): its
# job is to say when to /compact by hand at a clean boundary, before auto-compact summarises
# mid-work. Claude Code's formula (vendored harness services/compact/autoCompact.ts:33-90;
# 2.1.280's minified D8() is the same):
#   effective = window (capped by CLAUDE_CODE_AUTO_COMPACT_WINDOW) − 20k kept for the summary
#   threshold = min(effective × CLAUDE_AUTOCOMPACT_PCT_OVERRIDE / 100, effective − 13k)
# PCT 70 on the 1M window gives 686k: compaction fires when the old gauge read 69%.
SUMMARY_RESERVE, COMPACT_BUFFER = 20_000, 13_000


def claude_env(name):
    """A var from Claude Code's env: this process's, else the "env" block of the user settings."""
    if os.environ.get(name):
        return os.environ[name]
    home = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    try:
        with open(os.path.join(home, "settings.json")) as fh:
            return str((json.load(fh).get("env") or {}).get(name) or "")
    except (OSError, ValueError, AttributeError):
        return ""


def compact_point(window):
    """Context tokens at which auto-compact fires; the whole window when it is switched off."""
    if any(claude_env(v).lower() in ("1", "true", "yes", "on") for v in ("DISABLE_AUTO_COMPACT", "DISABLE_COMPACT")):
        return window
    cap = claude_env("CLAUDE_CODE_AUTO_COMPACT_WINDOW")
    if cap.isdigit() and int(cap) > 0:
        window = min(window, int(cap))
    effective = window - SUMMARY_RESERVE
    point = effective - COMPACT_BUFFER
    try:
        pct = float(claude_env("CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"))
    except ValueError:
        pct = 0
    if 0 < pct <= 100:
        point = min(int(effective * pct / 100), point)
    return point


def ctx_toward_compact(j):
    """How far the context is toward auto-compact: 1.0 = it fires. The token count is the one
    Claude Code's used_percentage is built from (input + cache writes + cache reads); after a
    /compact current_usage is null until the next call, so fall back to used_percentage."""
    window = get(j, "context_window", "context_window_size") or 0
    cu = get(j, "context_window", "current_usage")
    if isinstance(cu, dict):
        used = sum(cu.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    else:
        used = (get(j, "context_window", "used_percentage") or 0) / 100 * window
    if not window or not used:
        return 0.0
    return min(1.0, used / compact_point(window))


def ctx_color(frac):
    """Blue, then orange with room left to checkpoint and /compact by hand, red when it's close."""
    return C_DEL if frac >= 0.95 else C_PENDING if frac >= 0.85 else C_CTX


DISPLAY_TZ = os.environ.get("KIRA_TZ") or os.environ.get("TZ") or "America/Los_Angeles"


def zone():
    try:
        from zoneinfo import ZoneInfo

        return ZoneInfo(DISPLAY_TZ)
    except Exception:
        return None


def fmt_reset(epoch):
    """fmtReset: '04:00pm' if today in Ed's zone, else 'Sun 02:00am'."""
    tz = zone()
    d = datetime.fromtimestamp(epoch, tz) if tz else datetime.fromtimestamp(epoch)
    now = datetime.now(tz) if tz else datetime.now()
    t = d.strftime("%I:%M%p").lower()
    return t if d.date() == now.date() else "%s %s" % (d.strftime("%a"), t)


def tok(n):
    if n >= 1e9:
        return "%.1fB" % (n / 1e9)
    if n >= 1e6:
        return "%.1fM" % (n / 1e6)
    if n >= 1e3:
        return "%dK" % jround(n / 1e3)
    return str(n)


def usd(n):
    if n == 0:
        return "—"
    if n < 100:
        return "$%.2f" % n
    return "${:,}".format(jround(n))


def usage_box(ledger, cols):
    """UsageBox compact: month + YTD, outer width = the row width."""
    W = cols - 4
    head = ["turns", "in", "out", "tokens", "opus", "fable", "total"]
    # kiracode's column width (min 9); when that can't fit, drop the least useful
    # columns (in, out, tokens, turns) and let the rest go down to 8 wide
    keep = list(range(len(head)))
    for drop in (1, 2, 3, 0):
        if 11 + len(keep) * 8 <= W:
            break
        keep.remove(drop)
    cw = max(8 if len(keep) < len(head) else 9, (max(60, W) - 11) // len(keep))
    cw = min(cw, max(8, (W - 11) // len(keep)))

    def fill(label, vals):
        return label.ljust(11) + "".join(vals[i].rjust(cw) for i in keep)

    def vals(p):  # p[family] = [turns, in, out, cache read, cache write, cost]
        t = [0] * 6
        for m in ("opus", "fable"):
            x = p.get(m, [0] * 6)
            for i in range(6):
                t[i] += x[i]
        opus, fable = p.get("opus", [0] * 6)[5], p.get("fable", [0] * 6)[5]
        return [str(t[0]), tok(t[1]), tok(t[2]), tok(t[1] + t[2] + t[3] + t[4]),
                usd(opus), usd(fable), usd(opus + fable)]

    def row(content, style):
        return KIRA_ICE + "│ " + R + style + content.ljust(W) + R + KIRA_ICE + " │" + R

    title = "USAGE"
    return [
        KIRA_ICE + "┌ " + title + " " + "─" * max(0, W - len(title)) + "┐" + R,
        row(fill("", head), DIM),
        row("─" * W, DIM),
        row(fill("This month", vals(ledger["month"])), BOLD),
        row(fill("YTD", vals(ledger["ytd"])), BOLD),
        KIRA_ICE + "└" + "─" * (W + 2) + "┘" + R,
    ]


# ---- background refresh ---------------------------------------------------------------


def age(path):
    try:
        return time.time() - os.stat(path).st_mtime
    except OSError:
        return float("inf")


def touch(path):
    with open(path, "a"):
        pass
    os.utime(path, None)


def access_token():
    raw = None
    if sys.platform == "darwin":
        try:
            raw = subprocess.run(
                ["security", "find-generic-password", "-a", os.environ.get("USER", ""), "-w",
                 "-s", "Claude Code-credentials"],
                capture_output=True, text=True, timeout=4).stdout.strip() or None
        except Exception:
            raw = None
    if not raw:
        home = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
        try:
            with open(os.path.join(home, ".credentials.json")) as f:
                raw = f.read()
        except OSError:
            return None
    try:
        o = json.loads(raw)["claudeAiOauth"]
    except Exception:
        return None
    if not o.get("accessToken") or (o.get("expiresAt") or 0) / 1000 <= time.time():
        return None  # expired: Claude Code refreshes it on its next call, not us
    return o["accessToken"]


def iso_epoch(s):
    if not s:
        return None
    import re

    # python 3.9's fromisoformat wants exactly 0 or 6 fraction digits
    s = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], s.replace("Z", "+00:00"))
    try:
        return datetime.fromisoformat(s).timestamp()
    except ValueError:
        return None


def refresh_usage():
    tok_ = access_token()
    if not tok_:
        return
    import urllib.request

    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={"Authorization": "Bearer " + tok_, "anthropic-beta": "oauth-2025-04-20",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=8) as r:
        u = json.load(r)
    fable = next((l for l in (u.get("limits") or [])
                  if l.get("kind") == "weekly_scoped"
                  and ((l.get("scope") or {}).get("model") or {}).get("display_name", "").lower() == "fable"), None)
    spent = ((u.get("spend") or {}).get("used")) or None
    out = {
        "five_pct": (u.get("five_hour") or {}).get("utilization"),
        "five_reset": iso_epoch((u.get("five_hour") or {}).get("resets_at")),
        "week_pct": (u.get("seven_day") or {}).get("utilization"),
        "week_reset": iso_epoch((u.get("seven_day") or {}).get("resets_at")),
        "fable_pct": fable.get("percent") if fable else None,
        "fable_reset": iso_epoch(fable.get("resets_at")) if fable else None,
        # fmtMoney: minor units placed by the exponent. Only ever what the API
        # states; balance is null on this plan, so it is not shown (balanceOf).
        "spent": (spent["amount_minor"] / 10 ** spent.get("exponent", 2)) if spent else None,
    }
    tmp = USAGE + ".%d.tmp" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(out, f)
    os.replace(tmp, USAGE)


def projects_roots():
    roots = []
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        roots.append(os.path.join(os.environ["CLAUDE_CONFIG_DIR"], "projects"))
    roots += [os.path.expanduser("~/.claude/projects"), os.path.expanduser("~/.kira/projects")]
    return list(dict.fromkeys(roots))


def transcripts(root, depth=0, out=None):
    """collectTranscripts: recurse (subagents live 4 levels down), cap depth 8, no symlinks."""
    out = [] if out is None else out
    if depth > 8:
        return out
    try:
        entries = list(os.scandir(root))
    except OSError:
        return out
    for e in entries:
        try:
            if e.is_dir(follow_symlinks=False):
                transcripts(e.path, depth + 1, out)
            elif e.name.endswith(".jsonl"):
                out.append(e.path)
        except OSError:
            pass
    return out


def merge_row(rows, key, row):
    """Fold another line of the same response into rows[key]. Every line of a
    response repeats its input and cache counts; output_tokens is partial on the
    early lines (8, 8, 1398) and final on the last, so max keeps the final count."""
    seen = rows.get(key)
    if seen is None:
        rows[key] = row
        return
    if row[0] < seen[0]:
        seen[0] = row[0]  # day of the earliest line
    for i in range(2, 7):
        if row[i] > seen[i]:
            seen[i] = row[i]


def scan(path, start, rows):
    """scanFile from byte offset `start`; returns the offset after the last full line.
    Transcripts are append-only, so a grown file is read from where the last scan
    stopped instead of from the top (kiracode re-reads the whole file).

    rows: response key -> [day, model, in, out, cache read, 5m write, 1h write]. A
    transcript writes one line per content block of a response, all carrying the
    response's usage, so lines are merged per (message.id, requestId). The rows are
    kept per file between scans because a response's lines can straddle two scans."""
    with open(path, "rb") as f:
        f.seek(start)
        data = f.read()
    end = data.rfind(b"\n")
    if end < 0:
        return start
    pos = start
    for line in data[: end + 1].split(b"\n"):
        line_at, pos = pos, pos + len(line) + 1
        if b'"output_tokens"' not in line:
            continue
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if not isinstance(o, dict) or o.get("type") != "assistant":
            continue
        msg = o.get("message") or {}
        u, model = msg.get("usage"), msg.get("model")
        if not u or not isinstance(model, str):
            continue
        ts = o.get("timestamp")
        if not family(model) or not isinstance(ts, str) or len(ts) < 10:
            continue
        mid, rid = msg.get("id"), o.get("requestId")
        mid, rid = (mid if isinstance(mid, str) else ""), (rid if isinstance(rid, str) else "")
        # either id alone still names one response; with neither, the line stands alone
        key = mid + "|" + rid if mid or rid else "line:%s:%d" % (path, line_at)
        # cache writes by TTL (1.25x vs 2x input); without the breakdown, all 5m (the
        # API default). Capped at the total: forked copies zero the total but not the 1h.
        w = u.get("cache_creation_input_tokens") or 0
        w1h = min(((u.get("cache_creation") or {}).get("ephemeral_1h_input_tokens") or 0), w)
        merge_row(rows, key, [ts[:10], model, u.get("input_tokens") or 0, u.get("output_tokens") or 0,
                              u.get("cache_read_input_tokens") or 0, w - w1h, w1h])
    return start + end + 1


def rollup(files, year, month_key):
    """Month + YTD per family: [turns, in, out, cache read, cache write, cost]. Each
    response counts once across ALL files, since a resumed session copies earlier
    responses into its own transcript; per-file rows are copied, never mutated."""
    merged = {}
    for c in files.values():
        for key, row in c["rows"].items():
            seen = merged.get(key)
            if seen is None:
                merged[key] = row
            else:
                merged[key] = list(seen)
                merge_row(merged, key, row)
    month = {"opus": [0] * 6, "fable": [0] * 6}
    ytd = {"opus": [0] * 6, "fable": [0] * 6}
    rates = {}
    for day, model, i, o, cr, w5, w1 in merged.values():
        if not day.startswith(year):
            continue
        r = rates.get(model) or rates.setdefault(model, rate_for(model))
        add = (1, i, o, cr, w5 + w1, (i * r[0] + o * r[1] + cr * r[2] + w5 * r[3] + w1 * r[4]) / 1e6)
        for dst, ok in ((ytd, True), (month, day.startswith(month_key))):
            if ok:
                t = dst[family(model)]
                for k in range(6):
                    t[k] += add[k]
    return month, ytd


def refresh_ledger():
    try:
        with open(LEDGER_FILES) as f:
            cache = json.load(f)
        cache = cache["files"] if cache.get("v") == LEDGER_FORMAT else {}
    except (OSError, ValueError, AttributeError, KeyError):
        cache = {}
    fresh = {}
    for root in projects_roots():
        for p in transcripts(root):
            try:
                st = os.stat(p)
            except OSError:
                continue
            c = cache.get(p)
            if c and c["mtime"] == st.st_mtime_ns and c["size"] == st.st_size:
                fresh[p] = c
                continue
            if c and st.st_size >= c["size"]:
                rows, off = c["rows"], c["offset"]  # appended: read the tail only
            else:
                rows, off = {}, 0  # new, or rewritten/shrunk: full scan
            try:
                off = scan(p, off, rows)
            except OSError:
                continue
            fresh[p] = {"mtime": st.st_mtime_ns, "size": st.st_size, "offset": off, "rows": rows}
    now = datetime.now(timezone.utc)
    year, month_key = "%04d" % now.year, "%04d-%02d" % (now.year, now.month)
    month, ytd = rollup(fresh, year, month_key)
    for path, obj in ((LEDGER_FILES, {"v": LEDGER_FORMAT, "files": fresh}),
                      (LEDGER, {"v": LEDGER_FORMAT, "month": month, "ytd": ytd, "monthKey": month_key})):
        tmp = path + ".%d.tmp" % os.getpid()
        with open(tmp, "w") as f:
            json.dump(obj, f, separators=(",", ":"))
        os.replace(tmp, path)


def background_refresh():
    import fcntl

    os.makedirs(CACHE, exist_ok=True)
    with open(os.path.join(CACHE, "refresh.lock"), "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return  # another refresher is running
        for marker, ttl, fn in ((USAGE + ".tried", USAGE_TTL, refresh_usage),
                                (LEDGER + ".tried", LEDGER_TTL, refresh_ledger)):
            if age(marker) >= ttl:
                touch(marker)  # back off a full TTL even if this attempt fails
                try:
                    fn()
                except Exception:
                    pass


def maybe_spawn_refresh():
    if age(USAGE + ".tried") < USAGE_TTL and age(LEDGER + ".tried") < LEDGER_TTL:
        return
    if age(os.path.join(CACHE, "spawned")) < 10:
        return  # one spawn per 10 s at most; the child's lock handles overlap
    try:
        os.makedirs(CACHE, exist_ok=True)
        touch(os.path.join(CACHE, "spawned"))
        # its own session, so Claude Code cancelling this render can't kill it
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "--refresh"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True, close_fds=True)
    except Exception:
        pass


# ---- repo state: commit / push / bake -------------------------------------------------
# Ed's "cpb" = commit, push, bake. Every repo shows three slots, ● / ▲ / ◆: green when
# done, orange + a count when pending (files uncommitted / commits unpushed / commits
# not yet in the running artifact). Repos with nothing to bake always show a green ◆.
# "Baked" means the running artifact has caught up with the code (Ed's cpb, memory feedback-cpb-standing-instruction):
#   kiracode  harness/dist/cli.js built after the last harness source commit, and the
#             brain (the process running dist/cli.js) started after that build
#   anima     anima-server's image pin (docker/compose.box.yaml "head-<sha>") has no
#             later commits touching what Dockerfile.server COPYs in
#   studio    no running process uses a kira-studio script that changed after it started
#             (panes/launchers load their code once; ◆ N = N processes need a relaunch)
#   kira      every installed copy of an ops script (e.g. ~/.dotfiles/bin/kira-boot-recover,
#             which systemd runs) matches kira/ops (◆ N = N copies differ)
# Each git call is 1-4 ms, so this runs inline. Repos that don't exist are skipped.
REPOS = [("kiracode", "~/projects/kiracode", "kiracode"), ("anima", "~/anima|~/projects/anima", "anima"),
         ("kira", "~/projects/kira", "kira-ops"), ("kira-studio", "~/projects/kira-studio", "studio"),
         ("dotfiles", "~/.dotfiles", None), ("skills", "~/.ai-skills", None)]  # "a|b" = first that exists
ANIMA_BAKED = ["docker/constraints.txt", "pyproject.toml", "src", "static"]  # Dockerfile.server:44-49
C_CLEAN, C_PENDING = rgb("#3fb950"), rgb("#f0883e")  # green = done, orange = pending


def git(path, *args):
    try:
        r = subprocess.run(["git", "-C", path] + list(args), capture_output=True, text=True, timeout=2)
        return r.stdout if r.returncode == 0 else None
    except Exception:
        return None


def process_start(needle):
    """Epoch start time of the newest process whose cmdline contains `needle` (Linux /proc)."""
    try:
        with open("/proc/stat") as f:
            btime = next(int(l.split()[1]) for l in f if l.startswith("btime"))
        hz = os.sysconf("SC_CLK_TCK")
    except Exception:
        return None
    best = None
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                if needle.encode() not in f.read():
                    continue
            with open("/proc/%s/stat" % pid) as f:
                start = btime + int(f.read().rsplit(")", 1)[1].split()[19]) / hz
            best = max(best or 0, start)
        except Exception:
            continue
    return best


def unbaked(kind, path):
    """How many commits the running artifact is behind (0 = baked)."""
    if kind == "kiracode":
        dist = os.path.join(path, "harness/dist")
        try:
            built = os.stat(os.path.join(dist, "cli.js")).st_mtime
        except OSError:
            return 0
        brain = process_start("harness/dist/cli.js")
        not_live = bool(brain and brain < built)  # rebuilt, but the brain wasn't restarted onto it
        stamp = load(os.path.join(dist, "build-stamp.json"))
        if stamp and stamp.get("harness_tree"):
            # by content (kiracode build.ts stamps the harness/ tree it built): commits
            # newer than the newest one whose harness/ equals what was built
            commits = (git(path, "rev-list", "-n", "50", "HEAD", "--", "harness") or "").split()
            trees = (git(path, "rev-parse", *["%s:harness" % c for c in commits]) or "").split() if commits else []
            n = next((i for i, t in enumerate(trees) if t == stamp["harness_tree"]), None)
            if n is None:  # built from edits never committed as-is: count from the build's base
                n = int((git(path, "rev-list", "--count", "%s..HEAD" % stamp.get("head", "HEAD"), "--", "harness") or "0").strip() or 0)
            return max(n, 1) if not_live else n
        # no stamp (a bundle from before build.ts wrote one): fall back to timestamps
        live = min(built, brain) if brain else built
        log = git(path, "log", "-n", "500", "--format=%ct", "--", "harness", ":!harness/dist") or ""
        return sum(1 for t in log.split() if int(t) > live)
    if kind == "anima":
        import re

        try:
            with open(os.path.join(path, "docker/compose.box.yaml")) as f:
                m = re.search(r"image:\s*docker-anima-server:head-([0-9a-f]{7,})", f.read())
        except OSError:
            return 0
        n = git(path, "rev-list", "--count", "%s..HEAD" % m.group(1), "--", *ANIMA_BAKED) if m else None
        return int(n) if n and n.strip().isdigit() else 0
    if kind == "studio":  # a ps scan costs ~45 ms, so reuse it for 10 s
        cached = os.path.join(CACHE, "studio-stale.json")
        c = load(cached)
        if c and c.get("repo") == path and age(cached) < 10:
            return c.get("n", 0)
        n = len(stale_processes(path))
        try:
            os.makedirs(CACHE, exist_ok=True)
            with open(cached, "w") as f:
                json.dump({"repo": path, "n": n}, f)
        except OSError:
            pass
        return n
    if kind == "kira-ops":
        return len(stale_copies(path))
    return 0


def _etime_s(t):
    """ps etime "[[dd-]hh:]mm:ss" -> seconds (GNU and BSD ps share this format)."""
    days, _, rest = t.rpartition("-")
    parts = [int(x) for x in rest.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    return (int(days) if days else 0) * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]


INTERPRETERS = re.compile(r"^(python[0-9.]*|bash|sh|zsh|dash|node|bun|uv)$")


def executed_script(argv):
    """The script a process is running: argv[0] itself, or the first non-option argument
    after an interpreter (python3 x.py, bash x.sh, uv run x.py). None when there isn't one."""
    if not argv:
        return None
    if not INTERPRETERS.match(os.path.basename(argv[0])):
        return argv[0]
    rest = argv[1:]
    if os.path.basename(argv[0]) == "uv" and rest[:1] == ["run"]:
        rest = rest[1:]
    skip = False
    for tok in rest:
        if skip:  # the value of an option like --with / -W
            skip = False
            continue
        if tok in ("-c", "-m", "-e"):
            return None  # inline code / a module, not a script file
        if tok in ("--with", "--python", "-p", "--project", "--directory", "-W", "-X"):
            skip = True
            continue
        if not tok.startswith("-"):
            return tok
    return None


def stale_processes(repo):
    """Running processes executing a script in `repo` that changed after they started
    (kira-studio's panes and launchers load their code once): a relaunch is pending.
    Relative script paths resolve against the process cwd (Linux /proc only)."""
    try:
        out = subprocess.run(["ps", "-axo", "pid=,etime=,args="], capture_output=True, text=True,
                             timeout=2).stdout
    except Exception:
        return []
    now, stale = time.time(), []
    for line in out.splitlines():
        try:
            pid, et, args = line.split(None, 2)
            started = now - _etime_s(et)
        except ValueError:
            continue
        script = executed_script(args.split())
        if not script:
            continue
        if not script.startswith("/"):
            try:
                script = os.path.join(os.readlink("/proc/%s/cwd" % pid), script)
            except OSError:
                continue
        if not script.startswith(repo + "/"):
            continue
        try:
            if os.path.isfile(script) and os.stat(script).st_mtime > started + 1:
                stale.append((pid, script))
        except OSError:
            pass
    return stale


# Installed copies of kira's ops scripts that systemd runs from elsewhere (e.g. the unit's
# ExecStart is ~/.dotfiles/bin/kira-boot-recover, a git-excluded copy of kira/ops/kira-boot-recover).
OPS_COPY_DIRS = ["~/.dotfiles/bin", "~/.local/bin"]


def stale_copies(repo):
    """kira/ops scripts whose installed (non-symlink) copy differs from the repo version."""
    ops, diff = os.path.join(repo, "ops"), []
    try:
        names = os.listdir(ops)
    except OSError:
        return []
    for d in OPS_COPY_DIRS:
        d = os.path.expanduser(d)
        for n in names:
            src, dst = os.path.join(ops, n), os.path.join(d, n)
            if not os.path.isfile(src) or os.path.islink(dst) or not os.path.isfile(dst):
                continue
            try:
                with open(src, "rb") as a, open(dst, "rb") as b:
                    if a.read() != b.read():
                        diff.append(dst)
            except OSError:
                pass
    return diff


def slot(glyph, n):
    """One c/p/b slot: green glyph when clean, orange glyph + count when pending."""
    return (C_CLEAN + glyph + R, glyph) if not n else (C_PENDING + "%s %d" % (glyph, n) + R, "%s %d" % (glyph, n))


def repo_states(cwd):
    """Every repo as 'name ●/▲/◆' — commit / push / bake (Ed's cpb) — the cwd's repo first.
    Returns [(plain, styled, pending)]."""
    out = []
    for name, paths, kind in REPOS:
        path = next((os.path.expanduser(p) for p in paths.split("|")
                     if os.path.isdir(os.path.join(os.path.expanduser(p), ".git"))), None)
        if not path:
            continue
        st = git(path, "status", "--porcelain=v2", "--branch")
        if st is None:
            continue
        dirty = sum(1 for l in st.splitlines() if l and not l.startswith("#"))
        ahead = 0
        for l in st.splitlines():
            if l.startswith("# branch.ab "):
                ahead = int(l.split()[2].lstrip("+"))
        bake = unbaked(kind, path)
        parts = [slot("●", dirty), slot("▲", ahead), slot("◆", bake)]
        plain = name + " " + "/".join(p for _, p in parts)
        styled = name + " " + (DIM + "/" + R).join(st_ for st_, _ in parts)
        entry = (plain, styled, bool(dirty or ahead or bake))
        first = cwd == path or cwd.startswith(path + "/")
        out.insert(0, entry) if first else out.append(entry)
    return out


def second_row(j, cwd, cols):
    """lines +/-  │  every repo's c/p/b state: ● commit / ▲ push / ◆ bake."""
    left_p, left_s = [], []
    added, removed = get(j, "cost", "total_lines_added"), get(j, "cost", "total_lines_removed")
    if added or removed:
        a_, r_ = str(added or 0), str(removed or 0)
        left_p.append("+%s/-%s" % (a_, r_))
        left_s.append(C_ADD + "+" + a_ + R + DIM + "/" + R + C_DEL + "-" + r_ + R)
    plain = " · ".join(left_p)
    styled = (DIM + " · " + R).join(left_s)
    repos = repo_states(cwd)
    if plain:
        plain += "  │  "
        styled += SEP
    # repos wrap onto extra rows (aligned under the first repo) rather than being dropped
    indent = len(plain) if len(plain) < cols // 2 else 0
    rows_p, rows_s = [plain], [styled]
    for i, (rp, rs, _) in enumerate(repos):
        sep = "  " if rows_p[-1].strip() and not rows_p[-1].endswith("│  ") else ""
        if len(rows_p[-1]) + len(sep) + len(rp) > cols and rows_p[-1].strip():
            rows_p.append(" " * indent)
            rows_s.append(" " * indent)
            sep = ""
        rows_p[-1] += sep + rp
        rows_s[-1] += sep + rs
    return "\n".join(rows_s)



# ---- render ---------------------------------------------------------------------------


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def get(d, *keys):
    for k in keys:
        if not isinstance(d, dict):
            return None
        d = d.get(k)
    return d


def fmt_tokens(n):
    if n >= 1_000_000 and n % 1_000_000 == 0:
        return "%dM" % (n // 1_000_000)
    return "%dk" % (n // 1000) if n >= 1000 else str(n)


def git_branch(cwd):
    try:
        return subprocess.run(["git", "-C", cwd, "branch", "--show-current"], capture_output=True,
                              text=True, timeout=1).stdout.strip()
    except Exception:
        return ""


def left_segments(j, cwd):
    """Row 1, left: (priority, plain_text, styled_text) groups; lowest priority drops first."""
    import socket

    home = os.path.expanduser("~")
    where = "~" + cwd[len(home):] if cwd == home or cwd.startswith(home + "/") else cwd
    who = "%s@%s" % (os.environ.get("USER") or "?", socket.gethostname().split(".")[0])
    segs = [(0, who, C_USER + who + R), (0, where, C_DIR + where + R)]

    branch = get(j, "worktree", "branch") or git_branch(cwd)
    if branch:
        segs.append((3, "on " + branch, DIM + "on " + R + branch))
    pr = get(j, "pr", "number")
    if pr:
        segs.append((9, "#%s" % pr, DIM + "#%s" % pr + R))

    def item(prio, text, style=""):
        return (prio, text, style + text + R) if text else None

    import re

    # "Opus 5.5 (1M context)" -> "Opus 5.5": the window size is already the ctx gauge's job
    name = re.sub(r"\s*\([\d.]+\s*[KkMm]?\s+context\)\s*$", "", get(j, "model", "display_name") or "")
    model = [item(1, name), item(2, get(j, "effort", "level"), DIM),
             item(6, "thinking" if get(j, "thinking", "enabled") else "", DIM),
             item(6, "fast" if get(j, "fast_mode") else "", DIM),
             item(8, get(j, "agent", "name"), DIM),
             item(8, get(j, "output_style", "name") if get(j, "output_style", "name") not in (None, "default") else "", DIM),
             item(8, get(j, "vim", "mode"), DIM)]
    cost = get(j, "cost", "total_cost_usd")
    dur = get(j, "cost", "total_duration_ms")
    hit = get(j, "prompt_cache", "hit_ratio")
    session = [item(7, get(j, "session_name"), C_CREDIT),
               item(4, "$%.2f" % cost if cost is not None else "", C_CREDIT),
               item(5, ("%dh%dm" % divmod(int(dur) // 60000, 60)) if dur and dur >= 3_600_000 else
                    ("%dm" % (int(dur) // 60000) if dur is not None else ""), C_CREDIT)]
    if isinstance(hit, (int, float)):
        session.append(item(6, "cache %d%%" % jround(hit * 100), C_CREDIT))
    return segs, [m for m in model if m], [x for x in session if x]


def build_left(segs, model, session, budget):
    """Join the groups, dropping the lowest-priority items until the row fits."""
    items = [("seg", i, s[0]) for i, s in enumerate(segs)] + \
            [("model", i, m[0]) for i, m in enumerate(model)] + \
            [("session", i, x[0]) for i, x in enumerate(session)]
    drop = set()

    def render():
        head = [s for i, s in enumerate(segs) if ("seg", i) not in drop]
        plain = "  ".join(s[1] for s in head)
        styled = "  ".join(s[2] for s in head)
        for name, grp in (("model", model), ("session", session)):
            keep = [x for i, x in enumerate(grp) if (name, i) not in drop]
            if keep:
                plain += "  │  " + " · ".join(x[1] for x in keep)
                styled += SEP + (DIM + " · " + R).join(x[2] for x in keep)
        return plain, styled

    plain, styled = render()
    for kind, i, prio in sorted(items, key=lambda x: -x[2]):
        if len(plain) <= budget or prio == 0:  # user@host and the dir always stay
            break
        drop.add((kind, i))
        plain, styled = render()
    return plain, styled


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--refresh":
        background_refresh()
        return
    try:
        j = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        j = {}
    if not isinstance(j, dict):
        j = {}
    maybe_spawn_refresh()

    cols = int(os.environ.get("COLUMNS") or 120) - 4  # Claude Code pads the row 2 + 2
    cwd = get(j, "workspace", "current_dir") or os.getcwd()
    now = time.time()
    usage = load(USAGE) or {}

    def window(stdin_key, pct_key, reset_key):
        pct = get(j, "rate_limits", stdin_key, "used_percentage")
        reset = get(j, "rate_limits", stdin_key, "resets_at")
        if pct is None:  # stdin rate_limits only arrive after the first API response
            pct, reset = usage.get(pct_key), usage.get(reset_key)
        if pct is None or (reset and reset <= now):
            return None, ""
        return pct, (" · " + fmt_reset(reset)) if reset else ""

    s_pct, s_sfx = window("five_hour", "five_pct", "five_reset")
    w_pct, w_sfx = window("seven_day", "week_pct", "week_reset")
    f_pct, f_sfx = None, ""
    if usage.get("fable_pct") is not None and not (usage.get("fable_reset") and usage["fable_reset"] <= now):
        f_pct = usage["fable_pct"]
        f_sfx = (" · " + fmt_reset(usage["fable_reset"])) if usage.get("fable_reset") else ""

    lines = []

    # Row 1: the "? for shortcuts" line — our session data left, ctx gauge right
    ctx = ctx_toward_compact(j)
    ctx_plain_w = gauge_w("ctx used", 12)
    segs, model, session = left_segments(j, cwd)
    plain, styled = build_left(segs, model, session, cols - ctx_plain_w - 1)
    ctx_gauge = bar_gauge("ctx used", ctx, ctx_color(ctx))
    if len(plain) + 1 + ctx_plain_w <= cols:
        lines.append(styled + " " * (cols - len(plain) - ctx_plain_w) + ctx_gauge)
    else:  # very narrow: the gauge gets its own row, still right-aligned
        lines += [styled, " " * max(0, cols - ctx_plain_w) + ctx_gauge]
    row2 = second_row(j, cwd, cols)
    if row2:
        lines += row2.split("\n")  # one list entry per row, so padding survives Claude Code's trim

    # StatusFooter's limit rows, laid out as two centred columns (Ed, 09-25): the "│"
    # sits at the row's centre on both rows; session over "extra usage spent" on the
    # left (credits right-aligned under the session bar, as kiracode does), weekly
    # over fable on the right (fable's label padded so its bar sits under weekly's).
    # A blank row before and after the pair.
    if s_pct is not None or w_pct is not None or f_pct is not None:
        spent = usage.get("spent")
        credits_plain = "extra usage spent: $%.2f" % spent if spent is not None else ""
        left_w = (cols - 3) // 2
        right_w = cols - 3 - left_w
        r_sfx = max(len(w_sfx) if w_pct is not None else 0, len(f_sfx) if f_pct is not None else 0)
        room = []
        if s_pct is not None:
            room.append(left_w - 2 - gauge_w("session limit", 0, s_sfx))
        if w_pct is not None or f_pct is not None:
            room.append(right_w - 2 - gauge_w("weekly limit", 0, " " * r_sfx))
        stacked = bool(room) and min(room) < 8  # too narrow for two columns
        if stacked:  # one centred column: session block above the weekly/fable block
            room = [cols - 2 - gauge_w("session limit", 0, s_sfx), cols - 2 - gauge_w("weekly limit", 0, " " * r_sfx)]
        gw = max(6 if stacked else 8, min([28] + room))  # kiracode's clamp, sized to fit

        left = []   # (plain_width, styled)
        if s_pct is not None:
            left.append((gauge_w("session limit", gw, s_sfx), bar_gauge("session limit", s_pct / 100, C_SESSION, gw, s_sfx)))
        if credits_plain:
            left.append((len(credits_plain), DIM + "extra usage spent: " + R + C_CREDIT + "$%.2f" % spent + R))
        right = []
        if w_pct is not None:
            right.append((gauge_w("weekly limit", gw, w_sfx), bar_gauge("weekly limit", w_pct / 100, C_WEEKLY, gw, w_sfx)))
        if f_pct is not None:
            right.append((gauge_w("fable limit", gw, f_sfx, len("weekly limit: ")),
                          bar_gauge("fable limit", f_pct / 100, C_FABLE, gw, f_sfx, len("weekly limit: "))))

        lb = max([w for w, _ in left] or [0])    # left block: right-aligned lines, centred
        rb = max([w for w, _ in right] or [0])   # right block: left-aligned lines, centred
        lpad = max(0, (left_w - lb) // 2)
        rpad = max(0, (right_w - rb) // 2)
        lines.append("")
        if stacked:
            for block, bw, right_align in ((left, lb, True), (right, rb, False)):
                pad = max(0, (cols - bw) // 2)
                for w_, styled in block:
                    lines.append(" " * (pad + (bw - w_ if right_align else 0)) + styled)
        else:
            for i in range(max(len(left), len(right))):
                lw_, lstyled = left[i] if i < len(left) else (0, "")
                rw_, rstyled = right[i] if i < len(right) else (0, "")
                cell_l = " " * (lpad + lb - lw_) + lstyled + " " * max(0, left_w - lpad - lb)
                cell_r = " " * rpad + rstyled
                lines.append(cell_l + DIM + " │ " + R + cell_r)
        lines.append("")

    # blank, then the USAGE ledger
    ledger = load(LEDGER)
    if ledger and ledger.get("v") == LEDGER_FORMAT:  # an older format waits for the next refresh
        if lines[-1] != "":
            lines.append("")
        lines += usage_box(ledger, cols)

    # Claude Code trims every status row and drops empty ones (2.1.280:
    # \`.flatMap((j)=>j.trim()||[])\`), and a leading reset escape doesn't survive its
    # renderer either. U+2800 (braille blank) is not whitespace, draws as one empty
    # cell, and so keeps both the spacer rows and a row's leading padding.
    out = []
    for line in lines:
        if not line.strip(" "):
            line = BLANK
        elif line.startswith(" "):
            line = BLANK + line[1:]
        out.append(line)
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
