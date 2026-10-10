.pragma library

// Pure search logic: no Quickshell or Qt imports, so `node --test tests/` can run it.
// MiseService / MiseRemote hand it their state as plain arguments.

// mise has no `pypi:` backend, its name is `pipx:`: search, lookup and installs all use that
function alias(q) {
    return q.replace(/^\s*pypi:/i, "pipx:");
}

// `npm:foo@1.2` / `foo[opt=x]` -> `npm:foo`  (npm:@scope/pkg keeps its @)
function bareName(n) {
    return n.replace(/\[.*\]$/, "").replace(/@[^/@:]*$/, "");
}

// "npm:foo@1[x=y]" -> {bare: "npm:foo", b: "npm", t: "foo"}; free text has b ""
function splitQuery(q) {
    const bare = bareName(q);
    const c = bare.indexOf(":");
    return {
        bare: bare,
        b: c > 0 ? bare.substring(0, c) : "",
        t: c > 0 ? bare.substring(c + 1) : bare
    };
}

// "npm:foo" -> "npm"; plain registry names -> "registry"
function backendOf(name) {
    const i = name.indexOf(":");
    return i > 0 ? name.substring(0, i) : "registry";
}

function isGithub(url) {
    return url.startsWith("https://api.github.com/");
}

var maxRegistry = 12;   // registry rows per query
var maxFree = 5;        // hits per backend for free text (no prefix)
var maxPrefixed = 15;   // hits for `backend:query`

// searcher for one deps.dev ecosystem; results mix packages and GitHub projects, keep the packages
function depsDev(system) {
    return {
        free: false,
        url: (t, n) => "https://deps.dev/_/search?q=" + encodeURIComponent(t) + "&system=" + system,
        parse: j => (j.results || []).filter(r => r.kind === "PACKAGE").map(r => ({
            name: r.name,
            desc: r.defaultVersion ? "latest " + r.defaultVersion : ""
        }))
    };
}

// Backends we can search. `free` = also searched for plain text; the rest only after their
// prefix, or free text would drown in results (and GitHub allows 10 searches/min unauthenticated).
// Not searchable (no usable API): aqua, gitlab, ubi, spm, http, s3, asdf, vfox.
var searchers = {
    npm: {
        free: true,
        // lowercase: npm ranks case-sensitively (`Playwright` does not list `playwright` in the top 5)
        // and new package names are always lowercase. Legacy `JSONStream`-style names are still
        // found by typing them exactly (exact-name check).
        url: (t, n) => "https://registry.npmjs.org/-/v1/search?size=" + n + "&text=" + encodeURIComponent(t.toLowerCase()),
        parse: j => (j.objects || []).map(o => ({
            name: o.package.name,
            desc: o.package.description
        }))
    },
    cargo: {
        free: true,
        url: (t, n) => "https://crates.io/api/v1/crates?per_page=" + n + "&q=" + encodeURIComponent(t),
        parse: j => (j.crates || []).map(o => ({
            name: o.name,
            desc: o.description
        }))
    },
    github: {
        free: false,
        url: (t, n) => t.includes("/") ? "" : "https://api.github.com/search/repositories?per_page=" + n + "&q=" + encodeURIComponent(t),
        parse: j => (j.items || []).map(o => ({
            name: o.full_name,
            desc: o.description
        }))
    },
    // anaconda.org searches every channel at once (up to 100 hits, 1-3 s) and ignores channel
    // filters: keep conda-forge, the channel mise installs from, best match first
    conda: {
        free: false,
        url: (t, n) => "https://api.anaconda.org/search?name=" + encodeURIComponent(t),
        parse: (j, t) => {
            const q = t.toLowerCase();
            const score = n => n === q ? 0 : n.startsWith(q) ? 1 : 2;
            return (Array.isArray(j) ? j : []).filter(o => o.owner === "conda-forge").sort((a, b) => score(a.name) - score(b.name) || a.name.length - b.name.length).map(o => ({
                name: o.name,
                desc: o.summary
            }));
        }
    },
    // PyPI and Go have no search API: use the one behind deps.dev's own website (Google's Open
    // Source Insights). Unofficial and undocumented, may change without notice.
    pipx: depsDev("pypi"),
    pypi: depsDev("pypi"),
    go: depsDev("go"),
    gem: {
        free: false,
        url: (t, n) => "https://rubygems.org/api/v1/search.json?query=" + encodeURIComponent(t),
        parse: j => (Array.isArray(j) ? j : []).map(o => ({
            name: o.name,
            desc: o.info
        }))
    },
    dotnet: {
        free: false,
        url: (t, n) => "https://azuresearch-usnc.nuget.org/query?take=" + n + "&q=" + encodeURIComponent(t),
        parse: j => (j.data || []).map(o => ({
            name: o.id,
            desc: o.description
        }))
    }
};

var backends = Object.keys(searchers);

// Exact-name check for `backend:tool`: URL that answers 200 if it exists, 404 if not ("" = cannot check).
var verifiers = {
    npm: t => "https://registry.npmjs.org/" + encodeURIComponent(t) + "/latest",
    cargo: t => "https://crates.io/api/v1/crates/" + encodeURIComponent(t),
    pipx: t => "https://pypi.org/pypi/" + encodeURIComponent(t) + "/json",
    pypi: t => "https://pypi.org/pypi/" + encodeURIComponent(t) + "/json",
    gem: t => "https://rubygems.org/api/v1/gems/" + encodeURIComponent(t) + ".json",
    conda: t => "https://api.anaconda.org/package/conda-forge/" + encodeURIComponent(t),
    dotnet: t => "https://api.nuget.org/v3-flatcontainer/" + encodeURIComponent(t.toLowerCase()) + "/index.json",
    // module path: capitals are escaped as !lower in the proxy protocol
    go: t => "https://proxy.golang.org/" + t.replace(/[A-Z]/g, c => "!" + c.toLowerCase()) + "/@latest",
    // no aqua: mise resolves its names with a registry embedded in its binary, which is not upstream's (see miseCheck)
    github: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
    ubi: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
    spm: t => /^[^/]+\/[^/]+$/.test(t) ? "https://api.github.com/repos/" + t : "",
    gitlab: t => t.includes("/") ? "https://gitlab.com/api/v4/projects/" + encodeURIComponent(t) : ""
};

// URL that checks whether a typed `backend:tool` exists; "" when the spec cannot be checked
// (unknown backend, git+/URL specs, a pattern the backend's URL needs is missing)
function verifyUrl(q) {
    const p = splitQuery(q);
    if (!p.t || !verifiers[p.b] || /:\/\/|^git\+/.test(p.t))
        return "";
    return verifiers[p.b](p.t);
}

// `backend:tool` that only mise can check, because it resolves the name itself: `aqua:jq`, `aqua:owner/repo`.
// Returns what to hand to `mise tool --json`, "" when it is not one.
function miseCheck(q) {
    const p = splitQuery(q);
    return p.b === "aqua" && p.t && !/:\/\/|^git\+/.test(p.t) ? p.bare : "";
}

// the answer of `mise tool --json` as an HTTP-like status (what gotVerify takes): 200 mise knows the name,
// 404 it does not, 0 no usable answer. A name it knows has a description or the checks it would run
// (`security`); an unknown one has neither.
function toolStatus(j) {
    if (!j || typeof j !== "object")
        return 0;
    return j.description || (Array.isArray(j.security) && j.security.length) ? 200 : 404;
}

// backends that get a search request for this query
function searchTargets(q, remoteSearch) {
    if (!remoteSearch || q.length < 2)
        return [];
    const p = splitQuery(q);
    // `@scope/...` and paths are not search terms
    if (p.t.length < 3 || /^[@/]|:\/\//.test(p.t))
        return [];
    return backends.filter(k => (p.b ? p.b === k : searchers[k].free) && searchers[k].url(p.t, 1));
}

// why a request failed ("" = 200). remaining = x-ratelimit-remaining header, code = curl's exit code
function failure(status, remaining, code) {
    if (status === 200)
        return "";
    if (status === 0)
        return code === 28 ? "timeout" : "offline";
    if (status === 429 || (status === 403 && remaining === "0"))
        return "rate limited";
    return `HTTP ${status}`;
}

// the answer of a search request as rows: [{name: "npm:foo", backend: "npm", desc}]
function parseHits(b, json, term) {
    return searchers[b].parse(json, term).slice(0, maxPrefixed).map(h => ({
        name: `${b}:${h.name}`,
        backend: b,
        desc: h.desc || ""
    }));
}

// one-line description from the answer of a verifier (npm, crates.io, PyPI, rubygems, conda, GitHub)
function describe(j) {
    if (!j)
        return "";
    const info = j.info;
    const d = j.description || (typeof info === "string" ? info : info && info.summary) || j.summary || (j.crate && j.crate.description) || "";
    return String(d).trim().replace(/\s+/g, " ").substring(0, 80);
}

// Search registry + accept any `backend:tool` (pipx:, npm:, cargo:, github:, ...)
// since the registry is only a curated subset of what mise can install.
// ctx: {registry: [{name, backend: "b:t b:t", desc}], installed: [names that count as installed where it would go],
//       tools: {name: version} there, remote, verified, unchecked, remoteSearch}
function search(query, ctx) {
    const raw = alias((query || "").trim());   // keep case: github:Owner/Repo, [opts] are case-sensitive
    const q = raw.toLowerCase();
    if (!q)
        return [];
    const out = [];
    const registry = ctx.registry || [];
    const remote = ctx.remote || [];
    const verified = ctx.verified || {};
    const unchecked = ctx.unchecked || {};
    const tools = ctx.tools || {};
    const isInstalled = n => (ctx.installed || []).includes(n);
    // name without `[opts]` / `@version`  (npm:@scope/pkg keeps its @)
    const bare = bareName(raw);
    const base = bare.toLowerCase();
    const c = raw.indexOf(":");
    const b = c > 0 ? base.substring(0, c) : "";
    const term = c > 0 ? base.substring(c + 1) : base;
    const reg = registry.find(r => r.name === base);
    // registry entries that list the typed `backend:tool`: the same package as the direct row, which absorbs them
    // (description, installed state) so each package shows once, not as `direct` plus one row per registry name
    // `aqua:ripgrep` has no owner: mise looks the name up in its registry and takes the entry's first aqua backend
    // (`aqua:BurntSushi/ripgrep`), so that is the package the row stands for
    let pkgKey = base;
    if (b === "aqua" && !term.includes("/")) {
        const e = registry.find(r => r.name === term);
        pkgKey = ((e ? e.backend.split(" ") : []).find(t => t.startsWith("aqua:")) || base).toLowerCase();
    }
    const samePkg = c > 0 ? registry.filter(r => r.backend.toLowerCase().split(" ").includes(pkgKey)) : [];
    // plain `backend:name` that a remote hit matches: fold the hit into the direct row (canonical
    // name, description) instead of listing the same package twice. crates.io treats - and _ alike.
    let norm = x => x;
    if (b === "cargo")
        norm = x => x.replace(/_/g, "-");
    else if (b === "pipx" || b === "pypi")
        norm = x => x.replace(/[-_.]+/g, "-");
    const same = (x, y) => norm(x) === norm(y);
    const exact = ctx.remoteSearch && b && raw === bare ? remote.find(r => r.backend === b && same(r.name.toLowerCase(), base)) : null;
    // `backend:tool`, `backend:tool@ver`, `backend:tool[opt=val]` or `registryname@ver`
    // -> passed to `mise use` as typed. Pinned/optioned entries are never "installed":
    // they (re)configure the tool.
    if (!raw.endsWith("@") && ((c > 0 && c < raw.length - 1) || (reg && bare !== raw))) {
        // a hit proves the package exists, even when the exact-name check said 404 (npm and gem
        // names are case-sensitive: `npm:Playwright` is not found, `npm:playwright` is)
        const vf = verified[bare];
        const regDesc = (samePkg.find(r => r.desc) || {}).desc || "";
        let v = vf;
        if (exact)
            v = {
                ok: true,
                desc: (vf && vf.ok && vf.desc) || exact.desc || regDesc
            };
        else if (vf && vf.ok)
            v = {
                ok: true,
                desc: vf.desc || regDesc
            };
        else if (!vf && samePkg.length)
            v = {
                ok: true,
                desc: regDesc
            };
        const name = exact ? exact.name : raw;
        let note = "";
        if (v) {
            const d = v.desc ? ` ${v.desc}` : "";
            note = v.ok ? ` · ✓${d}` : " · ✗ not found";
        } else if (bare in unchecked)
            note = " · ? could not check";
        let kind = `${v && v.ok ? "" : "direct · "}${c > 0 ? raw.substring(0, c) : reg.backend}`;
        if (isInstalled(bare) && bare !== raw)
            kind = `re-pin ${bare} (now ${tools[bare] || "?"})`;
        out.push({
            name: name,
            backend: kind + note,
            installed: raw === bare && (isInstalled(name) || samePkg.some(r => isInstalled(r.name))),
            direct: true
        });
    }
    // `backend:term`: the registry lists `aqua:BurntSushi/ripgrep`, which does not contain `aqua:ripg`. Look for the term
    // after the prefix, as the remote search does: one row per `backend:...` entry, named as mise takes it
    const tokens = new Map();
    if (c > 0)
        for (const r of registry)
            for (const t of r.backend.split(" ")) {
                const rest = t.substring(b.length + 1).toLowerCase();
                if (!t.toLowerCase().startsWith(`${b}:`) || !rest.includes(term) || t.toLowerCase() === pkgKey || t.toLowerCase() === base)
                    continue;
                const e = tokens.get(t) || {
                    name: t,
                    rest: rest,
                    desc: "",
                    installed: false
                };
                e.desc = e.desc || r.desc || "";
                e.installed = e.installed || isInstalled(r.name) || isInstalled(t);
                tokens.set(t, e);
            }
    const tail = e => e.rest.split("/").pop();
    const tokenScore = e => {
        const t = tail(e);
        if (t === term)
            return 0;
        if (t.startsWith(term))
            return 1;
        return t.includes(term) ? 2 : 3;
    };
    for (const e of Array.from(tokens.values()).sort((x, y) => tokenScore(x) - tokenScore(y) || x.rest.length - y.rest.length).slice(0, maxRegistry))
        out.push({
            name: e.name,
            backend: e.desc ? `${b} · ${e.desc}` : b,
            installed: e.installed,
            direct: false
        });
    const hits = c > 0 ? [] : registry.filter(r => r.name.includes(base) || r.backend.toLowerCase().includes(base));
    // exact > prefix > substring > backend-only match, then shortest name
    const score = r => {
        if (r.name === base)
            return 0;
        if (r.name.startsWith(base))
            return 1;
        return r.name.includes(base) ? 2 : 3;
    };
    hits.sort((a, b) => score(a) - score(b) || a.name.length - b.name.length);
    // names with the same backends are one package (`rg`/`ripgrep`, `node`/`nodejs`). Shown: the installed one,
    // else the one typed, else the real name (the tool part of a backend: `ripgrep`, not its alias `rg`)
    const canon = r => r.backend.toLowerCase().split(" ").some(t => t.split(/[:/]/).pop() === r.name);
    const pref = r => (isInstalled(r.name) ? 4 : 0) + (r.name === base ? 2 : 0) + (canon(r) ? 1 : 0);
    const byPkg = new Map();   // keeps the position of the first one
    for (const r of hits) {
        const k = byPkg.get(r.backend);
        if (!k || pref(r) > pref(k))
            byPkg.set(r.backend, r);
    }
    for (const r of Array.from(byPkg.values()).slice(0, maxRegistry))
        out.push({
            name: r.name,
            backend: r.backend,
            installed: isInstalled(r.name),
            direct: false
        });
    // remote hits for what is being typed: free text -> backends marked `free`, `backend:q` -> that one.
    // Older hits that still match stay visible while the next request is in flight.
    const cap = b ? maxPrefixed : maxFree;   // per backend
    const seen = {};
    if (ctx.remoteSearch && term)
        for (const r of remote) {
            if (!(b ? r.backend === b : searchers[r.backend].free) || !r.name.toLowerCase().includes(term) || r.name === raw || out.some(o => o.name === r.name))
                continue;
            seen[r.backend] = (seen[r.backend] || 0) + 1;
            if (seen[r.backend] > cap)
                continue;
            out.push({
                name: r.name,
                backend: `${r.backend} · ${r.desc}`,
                installed: isInstalled(r.name),
                direct: false
            });
        }
    return out;
}

// `mise ls --json` run outside any project -> what the GLOBAL scope has: {installed: [names], missing: [names], versions: {name: active}}.
// Only a tool that a config declares counts (some entry has a `source`). `mise ls` also lists what is installed but
// declared nowhere, or only by a project: those have no `source` and are not the global's, so the global must not
// show them (it would offer to remove what other projects use). The projects filter the same way (`source.path`).
// `missing` = declared and not installed.
function parseGlobalLs(d) {
    const keys = Object.keys(d || {}).filter(k => Array.isArray(d[k]) && d[k].some(x => x.source));
    const has = k => d[k].some(x => x.installed);
    const versions = {};
    for (const k of keys)
        versions[k] = (d[k].find(x => x.active) || d[k][0] || {}).version || "";
    return {
        installed: keys.filter(has),
        missing: keys.filter(k => !has(k)),
        versions: versions
    };
}

// The bin of a version chip in a tool's details: "version" = remove just that version, "tool" = remove the tool from
// the row's scope (what the bin of the row does), "" = no bin. `c`: have (installed), inUse (the active one in the
// scope), removable (no tracked config uses it: mise's prunable list), sole (the only installed version), declared
// (the row's scope declares the tool). A version nobody uses can go on its own. The active one cannot: the config
// would ask for what is gone. Only when it is the tool's only version is it the tool itself, and then the bin does
// what the row's bin does: `unuse`, and uninstall unless another config declares it.
function versionBin(c) {
    if (!c.have)
        return "";
    if (!c.inUse)
        return c.removable ? "version" : "";
    return c.sole && c.declared ? "tool" : "";
}

// `mise settings ls --all --json-extended` -> [{key, type, value, desc, set, section}]. Nested groups become
// dotted keys (`npm.package_manager`); arrays show as `a,b`, the form `mise settings set` takes back. Only a
// setting the user wrote in a config carries a `source`. Sections: "Configured" (those, first), then
// "General" (no group) and one per group (`npm`, `github`...), alphabetical.
function parseSettings(json) {
    const out = [];
    const walk = (prefix, o) => {
        for (const k of Object.keys(o)) {
            const v = o[k];
            if (!v || typeof v !== "object")
                continue;
            if ("type" in v && "description" in v) {
                let section = "General";
                if (v.source)
                    section = "Configured";
                else if (prefix)
                    section = prefix.slice(0, -1);
                out.push({
                    key: `${prefix}${k}`,
                    type: v.type,
                    value: Array.isArray(v.value) ? v.value.join(",") : String(v.value ?? ""),
                    desc: v.description || "",
                    set: Boolean(v.source),
                    section: section
                });
            } else
                walk(`${prefix}${k}.`, v);
        }
    };
    walk("", json);
    const rank = s => {
        if (s === "Configured")
            return 0;
        return s === "General" ? 1 : 2;
    };
    return out.sort((a, b) => rank(a.section) - rank(b.section) || a.section.localeCompare(b.section) || a.key.localeCompare(b.key));
}

// settings whose name or description contains `q` (case-insensitive)
function filterSettings(list, q) {
    const t = q.trim().toLowerCase();
    return t ? list.filter(s => s.key.includes(t) || s.desc.toLowerCase().includes(t)) : list;
}
