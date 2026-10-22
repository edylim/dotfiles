#!/usr/bin/env python3
"""Tests for statusline.py's auto-compact point and the window it resolves from.

Offline, no deps:  python3 claude/.claude/statusline.test.py
(compact-nudge.test.js covers the hook and the gauge round trip; this covers
compact_point's window resolution: env cap, then the merged autoCompactWindow
setting for the session's model, then today's model-default path. Bundle facts
(Claude Code 2.1.296): resolution order is env CLAUDE_CODE_AUTO_COMPACT_WINDOW,
else the settings value for the canonical model key, else the model default, and
window = min(contextWindow, configured). Settings merge (QVt): sources in order
user, project .claude/settings.json, project .claude/settings.local.json; within
one file modelSettings[model] replaces that file's top-level value for the model;
a later file with a top-level value replaces the default AND resets byModel to
that file's modelSettings; a later file without one merges its modelSettings over.
Accepted values: 100000 to 1000000; "auto", junk and out-of-range are no setting.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import statusline  # noqa: E402

STATUSLINE = os.path.join(HERE, "statusline.py")
SID = "cccccccc-3333-4333-8333-cccccccccccc"
MODEL = "claude-opus-5-5"
WINDOW = 1_000_000

# PCT 70 everywhere below: point = min(effective*0.7, effective-13000), effective = window-20000
#   window 1M -> 686000 (today's), 300000 -> 196000, 400000 -> 266000,
#   450000 -> 301000, 500000 -> 336000, 200000 -> 126000


def call_point(window, model, cwd):
    """compact_point with the model/cwd args; falls back to the old single-arg signature
    so the tests that must keep passing on the pre-fix code do run there."""
    try:
        return statusline.compact_point(window, model, cwd)
    except TypeError:
        return statusline.compact_point(window)


class Env(unittest.TestCase):
    """Runs compact_point with CLAUDE_CONFIG_DIR and the project dir under a temp tree,
    and only the env vars a test names set (the ambient session's never leak in)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="statusline-acw-")
        self.conf = os.path.join(self.tmp, "config")
        self.cwd = os.path.join(self.tmp, "proj")
        os.makedirs(self.conf)
        os.makedirs(self.cwd)
        self._saved = {}
        for v in ("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "DISABLE_AUTO_COMPACT",
                  "DISABLE_COMPACT", "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE", "CLAUDE_CONFIG_DIR"):
            self._saved[v] = os.environ.pop(v, None)
        os.environ["CLAUDE_CONFIG_DIR"] = self.conf
        os.environ["CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"] = "70"

    def tearDown(self):
        for v, val in self._saved.items():
            if val is None:
                os.environ.pop(v, None)
            else:
                os.environ[v] = val
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write_user(self, body):
        self._write(os.path.join(self.conf, "settings.json"), body)

    def write_project(self, body, local=False):
        name = "settings.local.json" if local else "settings.json"
        self._write(os.path.join(self.cwd, ".claude", name), body)

    @staticmethod
    def _write(path, body):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(body if isinstance(body, str) else json.dumps(body))

    def point(self, window=WINDOW, model=MODEL):
        return call_point(window, model, self.cwd)


class TestWorkedExample(Env):
    def test_settings_window_gives_the_worked_point(self):
        # /autocompact 300 saved by Claude Code: window 300000, PCT 70 -> 196000
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        self.assertEqual(self.point(), 196_000)

    def test_bracket_1m_model_id_matches_the_canonical_key(self):
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        self.assertEqual(self.point(model="claude-opus-5-5[1m]"), 196_000)

    def test_dated_model_id_matches_the_canonical_key(self):
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        self.assertEqual(self.point(model="claude-opus-5-5-20261001"), 196_000)

    def test_top_level_auto_compact_window_applies_to_every_model(self):
        self.write_user({"autoCompactWindow": 300000})
        self.assertEqual(self.point(), 196_000)
        self.assertEqual(self.point(model="claude-fable-5-1"), 196_000)


class TestMerge(Env):
    def test_project_top_level_replaces_user_and_resets_by_model(self):
        # user sets byModel 200000; project sets a top level 450000 with no modelSettings:
        # the later top level replaces the default AND resets byModel -> the model gets 450000
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 200000}}})
        self.write_project({"autoCompactWindow": 450000})
        self.assertEqual(self.point(), 301_000)

    def test_project_model_settings_override_without_a_top_level(self):
        # user top level 300000; project (no top level) adds a modelSettings entry: merged
        # over the earlier byModel -> this model gets 500000, other models keep 300000
        self.write_user({"autoCompactWindow": 300000})
        self.write_project({"modelSettings": {MODEL: {"autoCompactWindow": 500000}}})
        self.assertEqual(self.point(), 336_000)
        self.assertEqual(self.point(model="claude-fable-5-1"), 196_000)

    def test_local_settings_override_project(self):
        self.write_user({"autoCompactWindow": 300000})
        self.write_project({"autoCompactWindow": 400000})
        self.write_project({"autoCompactWindow": 500000}, local=True)
        self.assertEqual(self.point(), 336_000)

    def test_model_settings_beat_the_top_level_in_the_same_file(self):
        self.write_user({"autoCompactWindow": 300000,
                         "modelSettings": {MODEL: {"autoCompactWindow": 500000}}})
        self.assertEqual(self.point(), 336_000)
        self.assertEqual(self.point(model="claude-fable-5-1"), 196_000)


class TestPrecedenceAndFallback(Env):
    def test_env_cap_beats_the_setting(self):
        # passes before the fix too (the env path already worked) and must keep passing
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        os.environ["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = "200000"
        self.assertEqual(self.point(), 126_000)

    def test_no_settings_is_today_behaviour(self):
        # passes before the fix too and must keep passing
        self.assertEqual(self.point(), 686_000)

    def test_auto_is_no_setting_and_does_not_block_a_later_value(self):
        # alone, "auto" must fall back to today's 686000; and a later file's modelSettings
        # must still apply over it (the reset keeps the later file's modelSettings)
        self.write_user({"autoCompactWindow": "auto"})
        self.assertEqual(self.point(), 686_000)
        self.write_project({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        self.assertEqual(self.point(), 196_000)

    def test_out_of_range_is_no_setting_and_does_not_block_a_later_value(self):
        # the bundle accepts 100000 to 1000000
        for junk in (50_000, 2_000_000, 0, -300000, "300k", None):
            with self.subTest(value=junk):
                shutil.rmtree(os.path.join(self.cwd, ".claude"), ignore_errors=True)  # clean slate per value
                self.write_user({"autoCompactWindow": junk})
                self.assertEqual(self.point(), 686_000)
                self.write_project({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
                self.assertEqual(self.point(), 196_000)

    def test_malformed_files_fall_back_and_never_raise(self):
        # a malformed user file is skipped, not fatal: the project's value still applies
        self.write_user("{not json")
        self.write_project({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        self.assertEqual(self.point(), 196_000)
        # malformed junk everywhere -> today's behaviour, still no exception
        self.write_user("[]")
        self.write_project("[]")
        self.write_project('{"modelSettings": {"%s": 42}}' % MODEL, local=True)
        self.assertEqual(self.point(), 686_000)
        # a settings.json that is a directory instead of a file
        os.remove(os.path.join(self.conf, "settings.json"))
        os.makedirs(os.path.join(self.conf, "settings.json"))
        self.assertEqual(self.point(), 686_000)


class TestGaugeFile(Env):
    """S3: the point the gauge file hooks/compact-nudge.js reads is the resolved one."""

    def render(self, used, extra=None):
        cache = os.path.join(self.tmp, "xdg")
        cdir = os.path.join(cache, "claude-statusline")
        os.makedirs(cdir, exist_ok=True)
        for m in ("usage.json.tried", "ledger.json.tried", "spawned"):
            open(os.path.join(cdir, m), "w").close()
        stdin = {
            "session_id": SID,
            "workspace": {"current_dir": self.cwd},
            "model": {"id": "claude-opus-5-5[1m]", "display_name": "Opus 5.5"},
            "context_window": {
                "context_window_size": WINDOW,
                "current_usage": {"input_tokens": 10, "cache_creation_input_tokens": 90,
                                  "cache_read_input_tokens": used - 100},
            },
            **(extra or {}),
        }
        env = dict(os.environ, XDG_CACHE_HOME=cache, CLAUDE_CONFIG_DIR=self.conf,
                   CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="70", COLUMNS="120")
        for v in ("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "DISABLE_AUTO_COMPACT", "DISABLE_COMPACT"):
            env.pop(v, None)
        r = subprocess.run([sys.executable, STATUSLINE], input=json.dumps(stdin), env=env,
                           encoding="utf8", cwd=self.tmp, capture_output=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        gpath = os.path.join(cdir, "ctx", SID + ".json")
        with open(gpath) as f:
            return json.load(f), r.stdout

    def test_gauge_file_carries_the_resolved_point(self):
        self.write_user({"modelSettings": {MODEL: {"autoCompactWindow": 300000}}})
        g, _ = self.render(176_400)  # 90% of 196000
        self.assertEqual(g["point"], 196_000)
        self.assertEqual(g["window"], WINDOW)
        self.assertEqual(g["used"], 176_400)
        self.assertEqual(g["frac"], 0.9)

    def test_gauge_file_without_settings_keeps_todays_point(self):
        g, _ = self.render(617_400)
        self.assertEqual(g["point"], 686_000)
        self.assertEqual(g["frac"], 0.9)


if __name__ == "__main__":
    unittest.main(verbosity=2)
