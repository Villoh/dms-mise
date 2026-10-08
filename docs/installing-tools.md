# Installing anything, with options

The registry is only a curated subset. Type any `backend:tool` and use it as-is:

```text
pipx:package
npm:package
cargo:crate
github:Owner/repo
```

Tool options go in brackets, exactly as `mise use` accepts them:

```text
pipx:package[uvx_args=--python 3.14]
npm:package[allow_builds=["node-pty"]]
```

They are written to the config as an inline table and kept on updates. Text is passed unchanged, so it is case-sensitive.

Tools that need several options, like the `http` backend, have a form: type `http:` and click the *custom download URL* row. Fill in the name, the download URL (with `{{version}}` in it) and a version list URL. If that list is JSON, add the path of the version in it (`.version`, `.[].tag_name`); if it is HTML or text, a regex with one capture group. Tick *List is not oldest first* for GitHub releases (and anything newest first): mise takes the last entry as `latest`, so without it you get the oldest release (`version_order=semver`). *Advanced* has `strip_components`, `bin_path`, `rename_exe`, `format` and `checksum_url` (read by `mise lock`, not by install; a fixed `checksum` is left out because it breaks on the next release).

You can also paste a `[tools."http:name"]` block (or a `"http:name" = { … }` line) from a mise.toml into the first field and it fills all of this. Under the fields you see the exact line `mise use` will get and, once you stop typing, what `latest` resolves to (`✓ latest resolves to 2.102.0` / `✗ No versions found`; a hint only, the button stays enabled). *Install latest* runs it:

```text
http:devin[url=https://static.devin.ai/cli/{{version}}/devin-{{version}}-x86_64-unknown-linux.tar.gz,version_list_url=https://static.devin.ai/cli/current/manifest.json,version_json_path=.version]@latest
```

The version list is what lets `latest` resolve and shows up in the version chips. No `checksum` is needed (it is a fixed value, so it would break on the next release).

Pin a version with `@`: `ripgrep@14.0.3` or `pipx:package@1.2`. The version part is *not* a prefix filter, it is what `mise use` writes, so `@14.0.3` pins exactly and `@14` follows the latest 14.x. (The separator is `@`, not `:`.) Entries with a version or options always show as installable, even if the tool is already installed, so you can re-pin or reconfigure it.

## Details and versions

Click a Tools row (the chevron shows its state) to expand it in place, one row at a time, with a short animation: description, backend, installed versions, a `latest` chip, and the latest 20 versions from the backend. The active version has a highlighted border, installed ones a ✓. Click a version to pin it (`mise use <tool>@<version>`, in the same scope as Install), which also lets you go back to an older release. `latest` writes `@latest`, so the tool follows the newest release; while the config says `latest`, that chip is the highlighted one and the version it resolved to only gets a ✓. Answers are cached until the panel is reloaded; a failed lookup is retried when you reopen the row.

Installed versions other than the active one carry a trash icon: click it, then click again to remove just that version (`mise uninstall tool@version`, the config is not touched). Installed versions too old to be in the latest 20 are listed as well. When a tool has versions that no tracked config uses, a *Prune N unused* button removes them. The Tools tab also gets a *Prune unused versions* button at the bottom for all tools. Pruning follows every config mise has tracked, not only the scope you picked.

## Live search and verification

Beyond the registry, typing in Tools (or the launcher) also queries the package sites, debounced (350 ms, 3+ characters):

- **free text**: registry (12) plus npm and crates.io (5 each), shown as `npm:name` / `cargo:name` with the description
- **`backend:q`**: that backend only, up to 15 hits. Searchable: `npm`, `cargo`, `github` (no `/`), `gem`, `dotnet`, `pipx` (`pypi:` is read as `pipx:`, mise has no `pypi` backend) and `go` (see below), `conda` (conda-forge only: anaconda.org searches every channel and takes 1-3 s). Other backends are not searched freely so plain text does not drown in results (GitHub also allows only 10 searches a minute unauthenticated)
- a typed `backend:tool` is checked against the site: `✓ description` or `✗ not found`. Verified: `npm`, `cargo`, `pipx`/`pypi`, `gem`, `conda` (conda-forge), `dotnet`, `go` (module path), `aqua`, `github`, `ubi`, `spm`, `gitlab` (`owner/repo`). A hint only, Enter still installs (private registries). When a search hit is the same package as what you typed (any capitalization; `-`/`_` for cargo), the two are one row, with the hit's canonical name and description. Entries with `@version` or `[options]` always stay as typed

No search for `aqua`, `gitlab` (search is unranked noise), `ubi`, `spm`, `http`, `s3`, `asdf`, `vfox`: exact name only, or use the registry. PyPI and Go have no search API (PyPI's was disabled in 2021 and `pypi.org/search` sits behind a JavaScript challenge), so `pipx:q`, `pypi:q` and `go:q` use the search behind [deps.dev](https://deps.dev)'s own website (Google's Open Source Insights): a plain JSON endpoint, ranked by relevance, no key. It is **unofficial and undocumented**, so it may change or disappear without notice; if it fails you get the notice below and the exact-name check still works. Rows show the latest version, not a description.

When a search request fails, the Tools tab (a line under the field) and the launcher (an extra last row) say which backend did not answer and why, e.g. `npm didn't answer · offline`. Reasons: `offline`, `timeout`, `rate limited` (`429`, or `403` with an exhausted `x-ratelimit-remaining`), `HTTP 5xx`, `unexpected answer`. That backend's hits are dropped instead of left on screen as if they answered the new query. Only backends the current query searches are mentioned, and the notice goes away as soon as a request to that backend succeeds. A `404` on the exact-name check is a real answer (`✗ not found`); any other failure shows `? could not check` on the row, and the notice gives the reason (`github didn't answer · rate limited`).

Turn all of this off in Settings (*Live search and verification*): only the registry is used and nothing you type leaves your machine.

### GitHub token

GitHub `owner/repo` checks and `github:q` search call `api.github.com`, which allows 60 requests/hour and 10 searches/minute unauthenticated (5000 and 30 with a token). On the first GitHub request the plugin runs `mise token github --raw` once and keeps the result in memory only. If mise has a token (`MISE_GITHUB_TOKEN`, `GITHUB_TOKEN`, `credential_command`, `gh`'s `hosts.yml`, ...), it is sent as `Authorization: Bearer` to `api.github.com` and to no other host, through a curl config on stdin so it never shows in `ps`. No token is fine: requests go unauthenticated, and a rate-limited answer shows `? could not check` instead of ✓/✗, and the notice says `github didn't answer · rate limited`. Nothing is looked up or sent while *Live search and verification* is off.

If `gh auth login` keeps its token in the system keyring, mise cannot read it and `mise token github` finds nothing. Tell mise to ask `gh`:

```toml
# ~/.config/mise/config.toml
[settings.github]
credential_command = "gh auth token"
```
