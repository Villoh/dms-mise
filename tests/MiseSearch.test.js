"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { load, fixture } = require("./load");

const S = load("MiseSearch.js");

const registry = [
    { name: "node", backend: "core:node" },
    { name: "nodejs", backend: "core:node" },
    { name: "ripgrep", backend: "aqua:BurntSushi/ripgrep cargo:ripgrep ubi:BurntSushi/ripgrep", desc: "recursive grep" },
    { name: "ripgrep-all", backend: "cargo:ripgrep_all" },
    { name: "fd", backend: "aqua:sharkdp/fd cargo:fd-find" },
    { name: "jq", backend: "aqua:jqlang/jq" }
].concat(Array.from({ length: 20 }, (_, i) => ({ name: "rip" + i, backend: "cargo:rip" + i })));

const hit = (backend, name, desc) => ({ name: backend + ":" + name, backend, desc: desc || "" });

function ctx(over) {
    return Object.assign({
        registry,
        installed: ["node", "ripgrep"],
        tools: { node: "22.1.0", ripgrep: "14.1.0" },
        remote: [],
        verified: {},
        unchecked: {},
        remoteSearch: true
    }, over);
}

test("helpers: alias, bareName, splitQuery, backendOf", () => {
    assert.equal(S.alias("pypi:ruff"), "pipx:ruff");
    assert.equal(S.alias("PyPI:ruff"), "pipx:ruff");
    assert.equal(S.alias("npm:left-pad"), "npm:left-pad");
    assert.equal(S.bareName("npm:foo@1.2"), "npm:foo");
    assert.equal(S.bareName("foo[opt=x]"), "foo");
    assert.equal(S.bareName("npm:@scope/pkg"), "npm:@scope/pkg");
    assert.equal(S.bareName("npm:@scope/pkg@2"), "npm:@scope/pkg");
    assert.deepEqual(S.splitQuery("npm:foo@1[x=y]"), { bare: "npm:foo", b: "npm", t: "foo" });
    assert.deepEqual(S.splitQuery("ripgrep"), { bare: "ripgrep", b: "", t: "ripgrep" });
    assert.equal(S.backendOf("npm:foo"), "npm");
    assert.equal(S.backendOf("node"), "registry");
});

test("search: empty query, @version and [options] stripping", () => {
    assert.deepEqual(S.search("", ctx()), []);
    assert.deepEqual(S.search("   ", ctx()), []);
    const rows = S.search("npm:foo@1.2[x=y]", ctx());
    assert.equal(rows[0].name, "npm:foo@1.2[x=y]", "typed as is, passed to mise use");
    assert.equal(rows[0].direct, true);
    assert.equal(rows[0].installed, false, "pinned entries are never installed");
    // trailing @ is still being typed: no direct row yet
    assert.ok(!S.search("npm:foo@", ctx()).some(r => r.direct));
});

test("search: npm:@scope/pkg keeps its @", () => {
    const rows = S.search("npm:@ai-sdk/google", ctx());
    assert.equal(rows[0].name, "npm:@ai-sdk/google");
    assert.equal(rows[0].backend, "direct · npm");
});

test("search: ranking exact > prefix > substring, then shortest; capped at 12", () => {
    const rows = S.search("node", ctx()).filter(r => !r.direct);
    assert.deepEqual(rows.slice(0, 2).map(r => r.name), ["node"], "nodejs lists the same backends: one package");
    assert.equal(rows[0].installed, true);
    const rip = S.search("rip", ctx()).filter(r => !r.direct);
    assert.equal(rip.length, S.maxRegistry);
    assert.equal(rip[0].name, "rip0", "shortest prefix match first");
    // backend text matches too (a `cargo:` search finds registry tools installed through cargo)
    assert.ok(S.search("fd-find", ctx()).some(r => r.name === "fd"));
});

test("search: registry names of one package are one row; the installed one wins", () => {
    assert.deepEqual(S.search("nod", ctx({ installed: [] })).map(r => r.name), ["node"]);
    const rows = S.search("nod", ctx({ installed: ["nodejs"] }));
    assert.deepEqual(rows.map(r => r.name), ["nodejs"]);
    assert.equal(rows[0].installed, true);
});

test("search: of one package, the real name shows rather than the alias, unless the alias is typed", () => {
    const reg = [{ name: "rg", backend: "aqua:BurntSushi/ripgrep cargo:ripgrep" }, { name: "ripgrep", backend: "aqua:BurntSushi/ripgrep cargo:ripgrep" }];
    const names = (q, over) => S.search(q, ctx(Object.assign({ registry: reg, installed: [] }, over))).map(r => r.name);
    assert.deepEqual(names("ripgre"), ["ripgrep"], "rg is shorter, ripgrep is the name");
    assert.deepEqual(names("rg"), ["rg"], "what was typed");
    assert.deepEqual(names("ripgre", { installed: ["rg"] }), ["rg"], "what is installed");
});

test("search: backend:term finds registry entries whatever the owner in between", () => {
    // the registry lists `aqua:BurntSushi/ripgrep`: it does not contain `aqua:ripg`
    const rows = S.search("aqua:ripg", ctx({ installed: [] }));
    assert.deepEqual(rows.map(r => r.name), ["aqua:ripg", "aqua:BurntSushi/ripgrep"]);
    assert.equal(rows[1].backend, "aqua · recursive grep");
    assert.equal(rows[1].direct, false);
    // the owner is searched too; other backends' entries are not listed
    assert.deepEqual(S.search("aqua:burnt", ctx()).map(r => r.name), ["aqua:burnt", "aqua:BurntSushi/ripgrep"]);
    assert.ok(S.search("aqua:ripg", ctx()).every(r => !r.name.startsWith("cargo:")));
    // the one that is installed through its registry name counts as installed
    assert.equal(S.search("aqua:ripg", ctx())[1].installed, true);
    // nothing matches: only the direct row
    assert.deepEqual(S.search("aqua:zzzz", ctx()).map(r => r.name), ["aqua:zzzz"]);
});

test("search: typed backend:tool listed in the registry folds its entries into the direct row", () => {
    // one row, with the description; `ripgrep` is installed, so is the package
    const rows = S.search("aqua:BurntSushi/ripgrep", ctx());
    assert.equal(rows.length, 1);
    assert.equal(rows[0].backend, "aqua · ✓ recursive grep");
    assert.equal(rows[0].direct, true);
    assert.equal(rows[0].name, "aqua:BurntSushi/ripgrep", "installs what was typed");
    assert.equal(rows[0].installed, true);
    assert.equal(S.search("cargo:ripgrep", ctx({ installed: [] }))[0].installed, false);
    // not in the registry: as before
    assert.equal(S.search("aqua:foo/bar", ctx())[0].backend, "direct · aqua");
    // the check of the site wins over the registry
    assert.equal(S.search("cargo:ripgrep", ctx({ verified: { "cargo:ripgrep": { ok: false } } }))[0].backend, "direct · cargo · ✗ not found");
    assert.equal(S.search("cargo:ripgrep", ctx({ verified: { "cargo:ripgrep": { ok: true, desc: "from crates.io" } } }))[0].backend, "cargo · ✓ from crates.io");
    // another package that merely contains the name is listed too, under the backend typed
    assert.deepEqual(S.search("cargo:ripgrep", ctx()).map(r => r.name), ["cargo:ripgrep", "cargo:ripgrep_all"]);
});

test("search: registryname@ver is a direct re-pin row for an installed tool", () => {
    const rows = S.search("node@20", ctx());
    assert.equal(rows[0].direct, true);
    assert.equal(rows[0].name, "node@20");
    assert.equal(rows[0].backend, "re-pin node (now 22.1.0)");
    // not installed: a plain pin on its registry backend
    assert.equal(S.search("jq@1.7", ctx())[0].backend, "direct · aqua:jqlang/jq");
});

test("search: project scope decides what counts as installed", () => {
    const c = ctx({ installed: ["jq"], tools: { jq: "1.7" } });
    const rows = S.search("jq", c);
    assert.equal(rows.find(r => r.name === "jq").installed, true);
    assert.equal(S.search("node", c).find(r => r.name === "node").installed, false);
});

test("search: remote hits follow the backend and the term, capped per backend", () => {
    const remote = Array.from({ length: 20 }, (_, i) => hit("npm", "rg-" + i, "npm " + i)).concat(Array.from({ length: 20 }, (_, i) => hit("cargo", "rg-" + i)), [hit("github", "BurntSushi/rg", "not free")]);
    const free = S.search("rg", ctx({ remote })).filter(r => !r.direct && r.name.includes(":"));
    assert.equal(free.filter(r => r.name.startsWith("npm:")).length, S.maxFree);
    assert.equal(free.filter(r => r.name.startsWith("cargo:")).length, S.maxFree);
    assert.equal(free.filter(r => r.name.startsWith("github:")).length, 0, "github is not searched for free text");
    const pre = S.search("npm:rg", ctx({ remote })).filter(r => !r.direct);
    assert.equal(pre.length, S.maxPrefixed);
    assert.ok(pre.every(r => r.name.startsWith("npm:")));
    assert.equal(pre[0].backend, "npm · npm 0");
    // the term filters older hits that no longer match; the exact one folds into the direct row
    const one = S.search("npm:rg-1", ctx({ remote }));
    assert.equal(one.length, 11);
    assert.equal(one[0].name, "npm:rg-1");
    assert.ok(one.slice(1).every(r => r.name.startsWith("npm:rg-1")));
    // off: registry only
    assert.equal(S.search("rg", ctx({ remote, remoteSearch: false })).filter(r => r.name.includes(":")).length, 0);
});

test("search: verification note on the direct row", () => {
    assert.equal(S.search("npm:foo", ctx({ verified: { "npm:foo": { ok: true, desc: "A foo" } } }))[0].backend, "npm · ✓ A foo");
    assert.equal(S.search("npm:foo", ctx({ verified: { "npm:foo": { ok: true, desc: "" } } }))[0].backend, "npm · ✓");
    assert.equal(S.search("npm:foo", ctx({ verified: { "npm:foo": { ok: false } } }))[0].backend, "direct · npm · ✗ not found");
    assert.equal(S.search("npm:foo", ctx({ unchecked: { "npm:foo": "offline" } }))[0].backend, "direct · npm · ? could not check");
    assert.equal(S.search("npm:foo", ctx())[0].backend, "direct · npm");
    // the note follows the bare name, the row keeps the version
    assert.equal(S.search("npm:foo@2", ctx({ verified: { "npm:foo": { ok: true, desc: "A foo" } } }))[0].name, "npm:foo@2");
});

// --- regressions from #9 ---

test("merge: npm:Playwright typed, npm:playwright found -> one row, canonical name, exists", () => {
    const c = ctx({ remote: [hit("npm", "playwright", "A high-level API")], verified: { "npm:Playwright": { ok: false } } });
    const rows = S.search("npm:Playwright", c);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].name, "npm:playwright");
    assert.equal(rows[0].backend, "npm · ✓ A high-level API", "a hit overrides a 404");
});

test("merge: cargo treats - and _ alike", () => {
    const c = ctx({ remote: [hit("cargo", "ripgrep-all", "rga")] });
    const rows = S.search("cargo:ripgrep_all", c).filter(r => r.name.startsWith("cargo:"));
    assert.deepEqual(rows.map(r => r.name), ["cargo:ripgrep-all"]);
    // other backends keep the distinction
    const n = ctx({ remote: [hit("npm", "left-pad")] });
    assert.equal(S.search("npm:left_pad", n).filter(r => r.direct).length, 1);
    assert.equal(S.search("npm:left_pad", n)[0].name, "npm:left_pad");
});

test("merge: pipx normalises -, _ and .", () => {
    const c = ctx({ remote: [hit("pipx", "ruff-lsp", "latest 0.0.62")] });
    assert.equal(S.search("pypi:ruff_lsp", c)[0].name, "pipx:ruff-lsp");
    assert.equal(S.search("pipx:Ruff.LSP", c)[0].name, "pipx:ruff-lsp");
});

test("merge: typed name and its hit with another capitalisation are one row", () => {
    const c = ctx({ remote: [hit("dotnet", "Avalonia", "A cross-platform UI framework")] });
    const rows = S.search("dotnet:avalonia", c);
    assert.equal(rows.filter(r => r.name.toLowerCase() === "dotnet:avalonia").length, 1);
    assert.equal(rows[0].name, "dotnet:Avalonia");
});

test("merge: @version and [options] stay as typed, no fold", () => {
    const c = ctx({ remote: [hit("npm", "playwright", "hit desc")], verified: { "npm:playwright": { ok: true, desc: "verified desc" } } });
    const rows = S.search("npm:playwright@1.40", c);
    assert.equal(rows[0].name, "npm:playwright@1.40");
    assert.equal(rows[0].backend, "npm · ✓ verified desc", "verification wins over the hit");
    // with a version typed nothing folds: the plain package is still offered as a hit
    assert.equal(rows[1].name, "npm:playwright");
    assert.equal(rows[1].backend, "npm · hit desc");
    const opt = S.search("npm:playwright[x=y]", c);
    assert.equal(opt[0].name, "npm:playwright[x=y]");
});

test("merge: description precedence, verification over hit", () => {
    const remote = [hit("npm", "playwright", "hit desc")];
    assert.equal(S.search("npm:playwright", ctx({ remote, verified: { "npm:playwright": { ok: true, desc: "verified desc" } } }))[0].backend, "npm · ✓ verified desc");
    assert.equal(S.search("npm:playwright", ctx({ remote, verified: { "npm:playwright": { ok: true, desc: "" } } }))[0].backend, "npm · ✓ hit desc");
    assert.equal(S.search("npm:playwright", ctx({ remote }))[0].backend, "npm · ✓ hit desc");
});

// --- parsers, on real answers ---

test("parse: npm", () => {
    const rows = S.parseHits("npm", fixture("npm-search"), "playwright");
    assert.equal(rows[0].name, "npm:playwright");
    assert.equal(rows[0].backend, "npm");
    assert.match(rows[0].desc, /browser/i);
    assert.deepEqual(S.parseHits("npm", {}, "x"), []);
});

test("parse: cargo", () => {
    const rows = S.parseHits("cargo", fixture("cargo-search"), "ripgrep");
    assert.ok(rows.some(r => r.name === "cargo:ripgrep"));
    assert.ok(rows.every(r => typeof r.desc === "string"));
    assert.deepEqual(S.parseHits("cargo", { crates: null }, "x"), []);
});

test("parse: github", () => {
    const rows = S.parseHits("github", fixture("github-search"), "mise");
    assert.ok(rows.some(r => r.name === "github:jdx/mise"));
    assert.deepEqual(S.parseHits("github", { message: "rate limited" }, "x"), []);
});

test("parse: gem", () => {
    const rows = S.parseHits("gem", fixture("gem-search"), "rails");
    assert.equal(rows[0].name, "gem:rails");
    assert.match(rows[0].desc, /Ruby on Rails/);
    assert.deepEqual(S.parseHits("gem", { error: "x" }, "x"), [], "an object instead of the array is not a hit");
});

test("parse: dotnet", () => {
    const rows = S.parseHits("dotnet", fixture("dotnet-search"), "avalonia");
    assert.equal(rows[0].name, "dotnet:Avalonia");
    assert.deepEqual(S.parseHits("dotnet", {}, "x"), []);
});

test("parse: conda keeps conda-forge only, best match first (owner is a string)", () => {
    const j = fixture("conda-search");
    assert.ok(j.some(o => o.owner === "anaconda"), "fixture has other channels");
    const rows = S.parseHits("conda", j, "ripgrep");
    assert.ok(rows.length > 0, "regression: filtering on owner.login returned nothing");
    assert.equal(rows[0].name, "conda:ripgrep");
    assert.equal(rows.length, j.filter(o => o.owner === "conda-forge").length);
    for (let i = 1; i < rows.length; i++)
        assert.ok(rows[i].name.length >= rows[i - 1].name.length || rows[i - 1].name === "conda:ripgrep");
    // an owner object (another API shape) matches nothing rather than throwing
    assert.deepEqual(S.parseHits("conda", [{ name: "x", owner: { login: "conda-forge" } }], "x"), []);
    assert.deepEqual(S.parseHits("conda", { error: "x" }, "x"), []);
});

test("parse: deps.dev keeps packages, drops GitHub projects; pipx/pypi/go share it", () => {
    const j = fixture("depsdev-search");
    assert.ok(j.results.some(r => r.kind === "PROJECT"));
    const rows = S.parseHits("pipx", j, "ruff");
    assert.ok(rows.length > 0);
    assert.ok(rows.every(r => r.name.startsWith("pipx:") && !r.name.includes("/")));
    assert.equal(rows[0].name, "pipx:ruff");
    assert.match(rows[0].desc, /^latest \d/);
    assert.equal(S.parseHits("pypi", j, "ruff")[0].name, "pypi:ruff");
    assert.equal(S.parseHits("go", j, "ruff")[0].name, "go:ruff");
    assert.deepEqual(S.parseHits("go", {}, "x"), []);
});

test("parse: capped at maxPrefixed", () => {
    const many = { objects: Array.from({ length: 40 }, (_, i) => ({ package: { name: "p" + i } })) };
    assert.equal(S.parseHits("npm", many, "p").length, S.maxPrefixed);
    assert.equal(S.parseHits("npm", many, "p")[0].desc, "", "missing description -> empty string");
});

// --- verifiers ---

test("verify: one URL per backend", () => {
    assert.equal(S.verifyUrl("npm:@scope/pkg"), "https://registry.npmjs.org/%40scope%2Fpkg/latest");
    assert.equal(S.verifyUrl("cargo:ripgrep"), "https://crates.io/api/v1/crates/ripgrep");
    assert.equal(S.verifyUrl("pipx:ruff"), "https://pypi.org/pypi/ruff/json");
    assert.equal(S.verifyUrl("pypi:ruff"), "https://pypi.org/pypi/ruff/json");
    assert.equal(S.verifyUrl("gem:rails"), "https://rubygems.org/api/v1/gems/rails.json");
    assert.equal(S.verifyUrl("conda:ripgrep"), "https://api.anaconda.org/package/conda-forge/ripgrep");
    assert.equal(S.verifyUrl("dotnet:Avalonia"), "https://api.nuget.org/v3-flatcontainer/avalonia/index.json");
    assert.equal(S.verifyUrl("go:github.com/BurntSushi/ripgrep"), "https://proxy.golang.org/github.com/!burnt!sushi/ripgrep/@latest");
    assert.equal(S.verifyUrl("aqua:BurntSushi/ripgrep"), "https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/BurntSushi/ripgrep/registry.yaml");
    assert.equal(S.verifyUrl("github:jdx/mise"), "https://api.github.com/repos/jdx/mise");
    assert.equal(S.verifyUrl("ubi:jdx/mise"), "https://api.github.com/repos/jdx/mise");
    assert.equal(S.verifyUrl("spm:jdx/mise"), "https://api.github.com/repos/jdx/mise");
    assert.equal(S.verifyUrl("gitlab:group/sub/project"), "https://gitlab.com/api/v4/projects/group%2Fsub%2Fproject");
    // the version is not part of the check
    assert.equal(S.verifyUrl("npm:foo@1.2[x=y]"), "https://registry.npmjs.org/foo/latest");
});

test("verify: \"\" for specs that cannot be checked", () => {
    assert.equal(S.verifyUrl("github:mise"), "", "owner/repo needed");
    assert.equal(S.verifyUrl("github:jdx/mise/extra"), "");
    assert.equal(S.verifyUrl("aqua:ripgrep"), "");
    assert.equal(S.verifyUrl("gitlab:project"), "");
    assert.equal(S.verifyUrl("http:foo"), "", "no verifier for that backend");
    assert.equal(S.verifyUrl("ripgrep"), "", "free text");
    assert.equal(S.verifyUrl("npm:"), "");
    assert.equal(S.verifyUrl("cargo:https://github.com/x/y"), "", "URL specs are not checked");
    assert.equal(S.verifyUrl("cargo:git+https://github.com/x/y"), "");
});

test("searchTargets: which backends a query asks", () => {
    assert.deepEqual(S.searchTargets("rip", true), ["npm", "cargo"]);
    assert.deepEqual(S.searchTargets("npm:rip", true), ["npm"]);
    assert.deepEqual(S.searchTargets("github:mise", true), ["github"]);
    assert.deepEqual(S.searchTargets("github:jdx/mise", true), [], "owner/repo is verified, not searched");
    assert.deepEqual(S.searchTargets("pypi:ruff", true), ["pypi"]);
    assert.deepEqual(S.searchTargets("npm:@scope", true), [], "scopes are not search terms");
    assert.deepEqual(S.searchTargets("ab", true), [], "too short");
    assert.deepEqual(S.searchTargets("rip", false), []);
    assert.deepEqual(S.searchTargets("aqua:ripgrep", true), [], "no searcher");
});

test("failure: why a request failed", () => {
    assert.equal(S.failure(200, "5", 0), "");
    assert.equal(S.failure(0, "", 28), "timeout");
    assert.equal(S.failure(0, "", 6), "offline");
    assert.equal(S.failure(429, "", 0), "rate limited");
    assert.equal(S.failure(403, "0", 0), "rate limited");
    assert.equal(S.failure(403, "12", 0), "HTTP 403");
    assert.equal(S.failure(500, "", 0), "HTTP 500");
});

// --- descriptions from verifier answers ---

test("describe: npm, crates.io, PyPI, rubygems, conda, GitHub", () => {
    assert.match(S.describe(fixture("npm-verify")), /browser/i);
    assert.match(S.describe(fixture("cargo-verify")), /ripgrep/i);
    assert.match(S.describe(fixture("pypi-verify")), /Python/i);
    assert.match(S.describe(fixture("gem-verify")), /Ruby on Rails/);
    assert.match(S.describe(fixture("conda-verify")), /ripgrep/i);
    assert.match(S.describe(fixture("github-verify")), /dev tools/i);
});

test("describe: trimmed to one line of 80 chars; odd shapes give \"\"", () => {
    assert.equal(S.describe({ description: "  a\n\n  b  " }), "a b");
    assert.equal(S.describe({ description: "x".repeat(100) }).length, 80);
    assert.equal(S.describe(null), "");
    assert.equal(S.describe({}), "");
    assert.equal(S.describe({ info: {} }), "");
    assert.equal(S.describe({ crate: {} }), "");
    assert.equal(S.describe("Not Found"), "", "npm answers a bare string on 404");
});

test("parseSettings: flattens groups, joins arrays, sections with set ones first", () => {
    const l = S.parseSettings({
        paranoid: { value: false, type: "boolean", description: "extra safe" },
        jobs: { value: 4, type: "number", description: "parallel", source: "/c.toml" },
        disable_hints: { value: ["a", "b"], type: "array", description: "hints" },
        npm: { package_manager: { value: "npm", type: "string", description: "which", source: "/c.toml" } }
    });
    assert.deepEqual(l.map(s => s.key), ["jobs", "npm.package_manager", "disable_hints", "paranoid"]);
    assert.deepEqual(l[0], { key: "jobs", type: "number", value: "4", desc: "parallel", set: true, section: "Configured" });
    assert.deepEqual(l.map(s => s.section), ["Configured", "Configured", "General", "General"]);
    assert.equal(l[2].value, "a,b");
    assert.equal(l[3].value, "false");
    assert.equal(l[3].set, false);
    assert.deepEqual(S.parseSettings({}), []);
});

test("filterSettings: name or description, any case", () => {
    const l = S.parseSettings({
        jobs: { value: 8, type: "number", description: "Parallel installs" },
        paranoid: { value: false, type: "boolean", description: "extra safe" }
    });
    assert.deepEqual(S.filterSettings(l, " JOB ").map(s => s.key), ["jobs"]);
    assert.deepEqual(S.filterSettings(l, "safe").map(s => s.key), ["paranoid"]);
    assert.equal(S.filterSettings(l, "").length, 2);
});
