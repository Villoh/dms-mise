"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { load } = require("./load");

const S = load("MiseScripts.js");
const scripts = ["project", "tracked", "resolve", "fix", "lockAfterUse", "locked", "uninstallUndeclared"];

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

test("uninstallUndeclared: uninstalls the tool, unless a tracked config still declares it", () => {
    const fs = require("node:fs");
    const os = require("node:os");
    const path = require("node:path");
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mise-"));
    // a fake mise: logs its arguments and whether it was handed a lockfile setting
    fs.writeFileSync(path.join(dir, "mise"), '#!/bin/sh\necho "LOCKFILE=${MISE_LOCKFILE-unset} $@" >> "$LOG"\n', { mode: 0o755 });
    const tracked = path.join(dir, "state", "tracked-configs");
    fs.mkdirSync(tracked, { recursive: true });
    const track = (name, text) => {
        const f = path.join(dir, name + ".toml");
        fs.writeFileSync(f, text);
        fs.symlinkSync(f, path.join(tracked, name));
    };
    const run = tool => {
        const log = path.join(dir, "log");
        fs.rmSync(log, { force: true });
        const r = spawnSync("sh", ["-c", S.uninstallUndeclared, "sh", tool], { encoding: "utf8", env: Object.assign({}, process.env, { PATH: dir + ":" + process.env.PATH, LOG: log, MISE_STATE_DIR: path.join(dir, "state") }) });
        // grep warns about an escape it does not need (`\/`), and that warning would end up in the job log
        assert.equal(r.stderr, "", tool);
        return { status: r.status, log: fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim() : "" };
    };
    track("global", '[tools]\nnode = "22"\n"aqua:sharkdp/fd" = "latest"\n"npm:@scope/pkg.js" = { version = "1" }\n[tools.ruff]\nversion = "1"\n');
    track("gone", "");
    fs.rmSync(path.join(dir, "gone.toml"));   // a tracked config that no longer exists is skipped
    // nobody declares it: uninstalled, and no mise setting is handed over
    assert.deepEqual(run("aqua:sharkdp/hyperfine"), { status: 0, log: "LOCKFILE=unset uninstall --yes --all aqua:sharkdp/hyperfine" });
    // declared as a plain key, a quoted key, a quoted key with regex characters and a table: kept, mise not called
    for (const t of ["node", "aqua:sharkdp/fd", "npm:@scope/pkg.js", "ruff"])
        assert.deepEqual(run(t), { status: 0, log: "" }, t);
    // a name that only contains a declared one, or differs by a regex character, is not declared
    assert.match(run("nod").log, /uninstall/);
    assert.match(run("aqua:sharkdp/f").log, /uninstall/);
    assert.match(run("npm:@scope/pkgXjs").log, /uninstall/, "the dot is not a wildcard");
    // a comment is not a declaration
    track("c", "# node = 1\n");
    assert.match(run("python").log, /uninstall/);
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
