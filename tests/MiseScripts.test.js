"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { load } = require("./load");

const S = load("MiseScripts.js");
const scripts = ["project", "tracked", "resolve", "fix", "lockAfterUse", "lockStale", "locked"];

test("every script is a non-empty string", () => {
    for (const k of scripts)
        assert.ok(typeof S[k] === "string" && S[k].length > 0, k);
});

test("every script parses with sh -n", () => {
    for (const k of scripts) {
        const r = spawnSync("sh", ["-n", "-c", S[k]], { encoding: "utf8" });
        assert.equal(r.status, 0, k + ": " + r.stderr);
    }
});

test("resolve: file, folder, ~ and errors (no mise needed)", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    const run = (arg, env) => spawnSync("sh", ["-c", S.resolve, "sh", arg], { encoding: "utf8", env: Object.assign({}, process.env, { MISE_GLOBAL_CONFIG_FILE: path.join(dir, "global.toml") }, env) });
    fs.writeFileSync(path.join(dir, "global.toml"), "");
    fs.mkdirSync(path.join(dir, "proj", ".config"), { recursive: true });
    fs.writeFileSync(path.join(dir, "proj", ".config", "mise.toml"), "");
    assert.equal(run(path.join(dir, "proj")).stdout.trim(), path.join(dir, "proj", ".config", "mise.toml"));
    assert.equal(run(path.join(dir, "proj", ".config", "mise.toml")).stdout.trim(), path.join(dir, "proj", ".config", "mise.toml"));
    assert.equal(run("~/proj", { HOME: dir }).stdout.trim(), path.join(dir, "proj", ".config", "mise.toml"));
    const g = run(path.join(dir, "global.toml"));
    assert.equal(g.status, 1);
    assert.match(g.stderr, /global config/);
    assert.match(run(path.join(dir, "nope")).stderr, /Not found/);
    fs.mkdirSync(path.join(dir, "empty"));
    assert.match(run(path.join(dir, "empty")).stderr, /No mise config/);
    fs.rmSync(dir, { recursive: true });
});

test("lockStale: `mise lock` only when mise says something is stale, for the scope that was edited", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    // a fake mise: logs its arguments; `--dry-run` answers what DRY says
    fs.writeFileSync(path.join(dir, "mise"), '#!/bin/sh\necho "$@" >> "$LOG"\ncase "$*" in *--dry-run*) [ -n "$DRY" ] && echo "$DRY";; esac\n', { mode: 0o755 });
    const run = (arg, dry) => {
        const log = path.join(dir, "log");
        fs.rmSync(log, { force: true });
        const r = spawnSync("sh", ["-c", S.lockStale, "sh", arg], { encoding: "utf8", env: Object.assign({}, process.env, { PATH: dir + ":" + process.env.PATH, LOG: log }, dry ? { DRY: dry } : {}) });
        return { status: r.status, calls: fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : [] };
    };
    const stale = "Dry run - would prune 1 stale tool entry from mise.lock: aqua:x/y";
    // global: -g
    assert.deepEqual(run("", stale), { status: 0, calls: ["lock -g --dry-run", "lock -g"] });
    // a project: in its folder
    assert.deepEqual(run("/p/q", stale), { status: 0, calls: ["-C /p/q lock --dry-run", "-C /p/q lock"] });
    // nothing stale, or no lockfile (mise says nothing): the lock is not touched, so none is created
    assert.deepEqual(run("", ""), { status: 0, calls: ["lock -g --dry-run"] });
    assert.deepEqual(run("/p/q", "Dry run - would update 3 platform entries"), { status: 0, calls: ["-C /p/q lock --dry-run"] });
    // a path with a space reaches mise as one argument
    assert.deepEqual(run("/my proj", stale).calls[1], "-C /my proj lock");
    fs.rmSync(dir, { recursive: true });
});

test("lockAfterUse: `latest` is locked with --bump and installed; a version is only locked", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    // a fake mise: logs its arguments; `settings get locked` answers what LOCKED says
    fs.writeFileSync(path.join(dir, "mise"), '#!/bin/sh\necho "$@" >> "$LOG"\ncase "$*" in *"settings get locked"*) echo "$LOCKED";; esac\n', { mode: 0o755 });
    const run = (prj, version, locked) => {
        const log = path.join(dir, "log");
        fs.rmSync(log, { force: true });
        const r = spawnSync("sh", ["-c", S.lockAfterUse, "sh", prj, "aqua:sharkdp/bat", version], { encoding: "utf8", env: Object.assign({}, process.env, { PATH: dir + ":" + process.env.PATH, LOG: log, LOCKED: locked === undefined ? "true" : locked }) });
        const calls = fs.readFileSync(log, "utf8").trim().split("\n").filter(c => !c.includes("settings get locked"));
        return { status: r.status, calls: calls };
    };
    // global: latest -> lock --bump, then install what it locked (use resolved `latest` through the old lock)
    assert.deepEqual(run("", "latest"), { status: 0, calls: ["lock -g --bump aqua:sharkdp/bat", "install --yes aqua:sharkdp/bat"] });
    // a concrete version is only locked, as before
    assert.deepEqual(run("", "0.26.0"), { status: 0, calls: ["lock -g aqua:sharkdp/bat"] });
    // a project: in its folder
    assert.deepEqual(run("/p", "latest"), { status: 0, calls: ["-C /p lock --bump aqua:sharkdp/bat", "-C /p install --yes aqua:sharkdp/bat"] });
    assert.deepEqual(run("/p", "0.26.0"), { status: 0, calls: ["-C /p lock aqua:sharkdp/bat"] });
    // without `locked` nothing runs: `mise lock` would create a lockfile nobody asked for
    assert.deepEqual(run("", "latest", "false"), { status: 0, calls: [] });
    fs.rmSync(dir, { recursive: true });
});

test("locked: `latest` is locked with --bump, a version is not", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    // a fake mise: logs its arguments (`config get` answers nothing, so the tool has no options)
    fs.writeFileSync(path.join(dir, "mise"), '#!/bin/sh\necho "$@" >> "$LOG"\n', { mode: 0o755 });
    const run = (cfg, prj, version) => {
        const log = path.join(dir, "log");
        fs.rmSync(log, { force: true });
        const r = spawnSync("sh", ["-c", S.locked, "sh", cfg, prj, "aqua:sharkdp/bat", version], { encoding: "utf8", env: Object.assign({}, process.env, { PATH: dir + ":" + process.env.PATH, LOG: log, MISE_GLOBAL_CONFIG_FILE: path.join(dir, "global.toml") }) });
        const calls = fs.readFileSync(log, "utf8").trim().split("\n");
        return { status: r.status, lock: calls.find(c => /(^| )lock( |$)/.test(c)) };
    };
    // global: `lock -g`, with --bump for latest only
    assert.deepEqual(run("", "", "latest"), { status: 0, lock: "lock -g --bump aqua:sharkdp/bat" });
    assert.deepEqual(run("", "", "0.26.0"), { status: 0, lock: "lock -g aqua:sharkdp/bat" });
    // a project: in its folder
    assert.deepEqual(run("/p/mise.toml", "/p", "latest"), { status: 0, lock: "-C /p lock --bump aqua:sharkdp/bat" });
    assert.deepEqual(run("/p/mise.toml", "/p", "0.26.0"), { status: 0, lock: "-C /p lock aqua:sharkdp/bat" });
    // a version that merely starts with `latest` is a version
    assert.equal(run("", "", "latest-1").lock, "lock -g aqua:sharkdp/bat");
    fs.rmSync(dir, { recursive: true });
});

test("fix: one failing config does not stop the others, and the job fails at the end", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    // a fake mise: logs its arguments, fails for the project called "bad"
    fs.writeFileSync(path.join(dir, "mise"), '#!/bin/sh\necho "$@" >> "$LOG"\ncase "$*" in *bad*) exit 1;; esac\n', { mode: 0o755 });
    const run = args => {
        const log = path.join(dir, "log");
        fs.rmSync(log, { force: true });
        const r = spawnSync("sh", ["-c", S.fix, "sh"].concat(args), { encoding: "utf8", env: Object.assign({}, process.env, { PATH: dir + ":" + process.env.PATH, LOG: log }) });
        return { status: r.status, log: fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : [] };
    };
    const lock = run(["unlocked", "/a/mise.toml", "/a", "unlocked", "/bad/mise.toml", "/bad", "unlocked", "", "", "unlocked", "/c/mise.toml", "/c"]);
    assert.equal(lock.status, 1);
    assert.deepEqual(lock.log, ["-C /a lock", "-C /bad lock", "lock -g", "-C /c lock"]);
    // each scope with its own kind: one waiting for a trust, the next ready to lock
    const mixed = run(["untrusted", "/a/mise.toml", "/a", "unlocked", "/c/mise.toml", "/c"]);
    assert.equal(mixed.status, 0);
    assert.deepEqual(mixed.log, ["trust /a/mise.toml", "-C /c lock"]);
    fs.rmSync(dir, { recursive: true });
});
