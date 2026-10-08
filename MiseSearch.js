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
    // the aqua registry is a folder per owner/repo
    aqua: t => /^[^/]+\/[^/]+/.test(t) ? "https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/" + t + "/registry.yaml" : "",
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
    return "HTTP " + status;
}

// the answer of a search request as rows: [{name: "npm:foo", backend: "npm", desc}]
function parseHits(b, json, term) {
    return searchers[b].parse(json, term).slice(0, maxPrefixed).map(h => ({
        name: b + ":" + h.name,
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
// ctx: {registry, installed: [names that count as installed where it would go], tools: {name: version} there,
//       remote, verified, unchecked, remoteSearch}
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
    // plain `backend:name` that a remote hit matches: fold the hit into the direct row (canonical
    // name, description) instead of listing the same package twice. crates.io treats - and _ alike.
    const norm = b === "cargo" ? x => x.replace(/_/g, "-") : (b === "pipx" || b === "pypi") ? x => x.replace(/[-_.]+/g, "-") : x => x;
    const same = (x, y) => norm(x) === norm(y);
    const exact = ctx.remoteSearch && b && raw === bare ? remote.find(r => r.backend === b && same(r.name.toLowerCase(), base)) : null;
    // `backend:tool`, `backend:tool@ver`, `backend:tool[opt=val]` or `registryname@ver`
    // -> passed to `mise use` as typed. Pinned/optioned entries are never "installed":
    // they (re)configure the tool.
    if (!raw.endsWith("@") && ((c > 0 && c < raw.length - 1) || (reg && bare !== raw))) {
        // a hit proves the package exists, even when the exact-name check said 404 (npm and gem
        // names are case-sensitive: `npm:Playwright` is not found, `npm:playwright` is)
        const vf = verified[bare];
        const v = exact ? {
            ok: true,
            desc: (vf && vf.ok && vf.desc) || exact.desc || ""
        } : vf;
        const name = exact ? exact.name : raw;
        const note = v ? (v.ok ? " · ✓" + (v.desc ? " " + v.desc : "") : " · ✗ not found") : bare in unchecked ? " · ? could not check" : "";
        out.push({
            name: name,
            backend: (isInstalled(bare) && bare !== raw ? "re-pin " + bare + " (now " + (tools[bare] || "?") + ")" : (v && v.ok ? "" : "direct · ") + (c > 0 ? raw.substring(0, c) : reg.backend)) + note,
            installed: raw === bare && isInstalled(name),
            direct: true
        });
    }
    const hits = registry.filter(r => r.name.includes(base) || r.backend.toLowerCase().includes(base));
    // exact > prefix > substring > backend-only match, then shortest name
    const score = r => r.name === base ? 0 : r.name.startsWith(base) ? 1 : r.name.includes(base) ? 2 : 3;
    hits.sort((a, b) => score(a) - score(b) || a.name.length - b.name.length);
    hits.slice(0, maxRegistry).forEach(r => out.push({
        name: r.name,
        backend: r.backend,
        installed: isInstalled(r.name),
        direct: false
    }));
    // remote hits for what is being typed: free text -> backends marked `free`, `backend:q` -> that one.
    // Older hits that still match stay visible while the next request is in flight.
    const cap = b ? maxPrefixed : maxFree;   // per backend
    const seen = {};
    if (ctx.remoteSearch && term)
        remote.filter(r => (b ? r.backend === b : searchers[r.backend].free) && r.name.toLowerCase().includes(term) && r.name !== raw && !out.some(o => o.name === r.name) && (seen[r.backend] = (seen[r.backend] || 0) + 1) <= cap).forEach(r => out.push({
            name: r.name,
            backend: r.backend + " · " + r.desc,
            installed: isInstalled(r.name),
            direct: false
        }));
    return out;
}

// `mise settings ls --all --json-extended` -> [{key, type, value, desc, set, section}]. Nested groups become
// dotted keys (`npm.package_manager`); arrays show as `a,b`, the form `mise settings set` takes back. Only a
// setting the user wrote in a config carries a `source`. Sections: "Configured" (those, first), then
// "General" (no group) and one per group (`npm`, `github`...), alphabetical.
function parseSettings(json) {
    const out = [];
    const walk = (prefix, o) => Object.keys(o).forEach(k => {
        const v = o[k];
        if (!v || typeof v !== "object")
            return;
        if ("type" in v && "description" in v)
            out.push({
                key: prefix + k,
                type: v.type,
                value: Array.isArray(v.value) ? v.value.join(",") : String(v.value ?? ""),
                desc: v.description || "",
                set: !!v.source,
                section: v.source ? "Configured" : prefix ? prefix.slice(0, -1) : "General"
            });
        else
            walk(prefix + k + ".", v);
    });
    walk("", json);
    const rank = s => (s === "Configured" ? 0 : s === "General" ? 1 : 2);
    return out.sort((a, b) => rank(a.section) - rank(b.section) || a.section.localeCompare(b.section) || a.key.localeCompare(b.key));
}

// settings whose name or description contains `q` (case-insensitive)
function filterSettings(list, q) {
    const t = q.trim().toLowerCase();
    return t ? list.filter(s => s.key.includes(t) || s.desc.toLowerCase().includes(t)) : list;
}
