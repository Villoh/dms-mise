"use strict";
// Loads a QML `.pragma library` file into a bare context, so its top-level functions and vars
// can be tested with the standard library only (no exports, no bundler).
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function load(file) {
    const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(/^\.pragma library\s*\n/, "");
    // same realm as the tests, so deepEqual works on what it returns
    const names = [...src.matchAll(/^(?:function|var) (\w+)/gm)].map(m => m[1]);
    return vm.runInThisContext("(function () {\n" + src + "\nreturn {" + names.join(", ") + "};\n})", { filename: file })();
}

function fixture(name) {
    return JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", name + ".json"), "utf8"));
}

module.exports = { load, fixture };
