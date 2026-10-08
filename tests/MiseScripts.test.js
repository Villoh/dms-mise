"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { load } = require("./load");

const S = load("MiseScripts.js");
const scripts = ["project", "tracked", "resolve", "lockAfterUse", "locked"];

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
