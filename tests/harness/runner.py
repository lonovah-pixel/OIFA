#!/usr/bin/env python3
"""Headless test runner for SITE-VEIL server logic.

Loads the SITE-VEIL gamemode (server realm only) into LuaJIT through lupa,
on top of tests/harness/gmod_mock.lua, with a fresh in-memory SQLite
database per test file. The real DarkRP and the GMod engine are NOT loaded:
these tests verify SITE-VEIL's own server logic only (see TESTING.md).

Usage: python3 -I tests/harness/runner.py [test_file ...]
"""

import json
import os
import sqlite3
import sys
import traceback

try:
    from lupa import luajit21 as lupa_impl
except ImportError:  # pragma: no cover
    import lupa as lupa_impl

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAMEMODES = os.path.join(ROOT, "gamemodes")
HARNESS = os.path.dirname(os.path.abspath(__file__))
TESTS = os.path.join(ROOT, "tests", "server")
CLIENT_TESTS = os.path.join(ROOT, "tests", "client")
ADDONS = os.path.join(ROOT, "addons")
ADDON_FIXTURES = os.path.join(ROOT, "tests", "fixtures", "addons")
# Push payloads recorded by server tests, replayed by the client smoke test.
FIXTURES = os.path.join(ROOT, "tests", ".fixtures", "pushes.json")


class Host:
    def __init__(self, extra_roots=None):
        self.extra_roots = extra_roots or []
        self.db = sqlite3.connect(":memory:", isolation_level=None)
        self.data = {}
        self.lua = lupa_impl.LuaRuntime(unpack_returned_tuples=True)

    # -- conversion helpers -------------------------------------------------
    def lua_to_py(self, value, depth=0):
        if depth > 64:
            raise ValueError("table too deep")
        if lupa_impl.lua_type(value) == "table":
            keys = list(value.keys())
            if keys and all(isinstance(k, (int, float)) and float(k).is_integer() for k in keys):
                ints = sorted(int(k) for k in keys)
                if ints == list(range(1, len(ints) + 1)):
                    return [self.lua_to_py(value[i], depth + 1) for i in ints]
            if not keys:
                return []
            out = {}
            for k in keys:
                v = value[k]
                if lupa_impl.lua_type(v) in ("function", "userdata", "thread"):
                    continue
                if isinstance(k, float) and k.is_integer():
                    k = int(k)
                out[str(k)] = self.lua_to_py(v, depth + 1)
            return out
        if lupa_impl.lua_type(value) in ("function", "userdata"):
            return None
        return value

    def py_to_lua(self, value):
        if isinstance(value, dict):
            t = self.lua.table()
            for k, v in value.items():
                key = k
                try:
                    num = float(k)
                    if num.is_integer():
                        key = int(num)
                    else:
                        key = num
                except (ValueError, TypeError):
                    pass
                t[key] = self.py_to_lua(v)
            return t
        if isinstance(value, list):
            t = self.lua.table()
            for i, v in enumerate(value):
                t[i + 1] = self.py_to_lua(v)
            return t
        return value

    # -- host functions -----------------------------------------------------
    def sql(self, query):
        try:
            cur = self.db.execute(query)
            if cur.description is None:
                return True, None
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            t = self.lua.table()
            for i, row in enumerate(rows):
                r = self.lua.table()
                for c, v in zip(cols, row):
                    if v is None:
                        r[c] = "NULL"  # GMod returns NULL as the string "NULL"
                    elif isinstance(v, float) and v.is_integer():
                        r[c] = str(int(v))
                    else:
                        r[c] = str(v)
                t[i + 1] = r
            return True, t
        except sqlite3.Error as exc:
            return False, str(exc)

    def json_encode(self, table):
        return json.dumps(self.lua_to_py(table), ensure_ascii=False)

    def json_decode(self, text):
        try:
            return self.py_to_lua(json.loads(text))
        except (ValueError, TypeError):
            return None

    # The Lua virtual filesystem of GMod: gamemodes/ plus every addon's lua/.
    def lua_roots(self):
        roots = [GAMEMODES]
        for base in [ADDONS] + self.extra_roots:
            if os.path.isdir(base):
                for name in sorted(os.listdir(base)):
                    lua = os.path.join(base, name, "lua")
                    if os.path.isdir(lua):
                        roots.append(lua)
        return roots

    def resolve(self, path):
        for root in self.lua_roots():
            full = os.path.normpath(os.path.join(root, path))
            if full.startswith(root) and os.path.isfile(full):
                return full
        return None

    def read(self, path):
        full = self.resolve(path)
        if not full:
            return None
        with open(full, encoding="utf-8") as fh:
            return fh.read()

    def exists(self, path):
        return self.resolve(path) is not None

    def find(self, pattern):
        """file.Find(pattern, "LUA") for patterns like "dir/*" or "dir/*.lua"."""
        import fnmatch
        base, _, mask = pattern.rpartition("/")
        files, dirs = set(), set()
        for root in self.lua_roots():
            full = os.path.normpath(os.path.join(root, base))
            if not full.startswith(root) or not os.path.isdir(full):
                continue
            for name in os.listdir(full):
                if fnmatch.fnmatch(name, mask):
                    (dirs if os.path.isdir(os.path.join(full, name)) else files).add(name)
        ft, dt = self.lua.table(), self.lua.table()
        for i, n in enumerate(sorted(files)):
            ft[i + 1] = n
        for i, n in enumerate(sorted(dirs)):
            dt[i + 1] = n
        return ft, dt

    def data_read(self, path):
        return self.data.get(path)

    def data_write(self, path, content):
        if content is None:
            self.data.pop(path, None)
        else:
            self.data[path] = content

    def data_exists(self, path):
        return path in self.data

    def list_dirs(self, path):
        full = os.path.normpath(os.path.join(GAMEMODES, path))
        t = self.lua.table()
        if full.startswith(GAMEMODES) and os.path.isdir(full):
            for i, name in enumerate(sorted(os.listdir(full))):
                t[i + 1] = name
        return t

    def install(self, client=False):
        g = self.lua.globals()
        g["__CLIENT_MODE"] = client
        g["__host_sql"] = self.sql
        g["__host_json_encode"] = self.json_encode
        g["__host_json_decode"] = self.json_decode
        g["__host_read"] = self.read
        g["__host_exists"] = self.exists
        g["__host_data_read"] = self.data_read
        g["__host_data_write"] = self.data_write
        g["__host_data_exists"] = self.data_exists
        g["__host_list"] = self.list_dirs
        g["__host_find"] = self.find
        g["__host_fixtures"] = lambda: open(FIXTURES, encoding="utf-8").read() if os.path.exists(FIXTURES) else None
        with open(os.path.join(HARNESS, "gmod_mock.lua"), encoding="utf-8") as fh:
            self.lua.execute(fh.read())
        if client:
            with open(os.path.join(HARNESS, "client_stubs.lua"), encoding="utf-8") as fh:
                self.lua.execute(fh.read())
        with open(os.path.join(HARNESS, "boot.lua"), encoding="utf-8") as fh:
            self.lua.execute(fh.read())


def save_push_samples(host):
    samples = host.lua_to_py(host.lua.globals().MOCK.pushSamples)
    if not isinstance(samples, dict):
        return
    os.makedirs(os.path.dirname(FIXTURES), exist_ok=True)
    merged = {}
    if os.path.exists(FIXTURES):
        with open(FIXTURES, encoding="utf-8") as fh:
            merged = json.load(fh)
    for event, payloads in samples.items():
        merged.setdefault(event, [])
        for p in payloads:
            if len(merged[event]) < 3 and p not in merged[event]:
                merged[event].append(p)
    with open(FIXTURES, "w", encoding="utf-8") as fh:
        json.dump(merged, fh, ensure_ascii=False, sort_keys=True)


def run_file(path):
    # Broken test addons are installed only for the loader robustness test.
    extra = [ADDON_FIXTURES] if os.path.basename(path).startswith("test_addon_loader") else []
    host = Host(extra)
    client = os.path.basename(os.path.dirname(os.path.abspath(path))) == "client"
    try:
        host.install(client)
    except Exception:  # noqa: BLE001 - report loader failures as test failure
        print(f"FAIL {os.path.basename(path)}: gamemode failed to load")
        traceback.print_exc()
        return 0, 1
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    host.lua.execute(f"TESTFILE = {json.dumps(os.path.basename(path))}")
    try:
        host.lua.execute(src)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {os.path.basename(path)}: {exc}")
        return 0, 1
    host.lua.execute("io.flush()")
    sys.stdout.flush()
    if not client:
        save_push_samples(host)
    result = host.lua.globals().TEST_RESULTS
    passed = int(result.passed)
    failed = int(result.failed)
    return passed, failed


def main(argv):
    files = argv or [
        os.path.join(d, f)
        for d in (TESTS, CLIENT_TESTS) if os.path.isdir(d)
        for f in sorted(os.listdir(d)) if f.endswith(".lua")
    ]
    if not argv and os.path.exists(FIXTURES):
        os.remove(FIXTURES)  # a full run records fresh samples
    total_pass = total_fail = 0
    for f in files:
        p, fl = run_file(f)
        total_pass += p
        total_fail += fl
    print(f"\n{total_pass} passed, {total_fail} failed")
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
