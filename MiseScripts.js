.pragma library

// Shell scripts run by MiseService through `sh -c`. Kept as line arrays: readable, no escaping of
// the `${...}` and quotes shell needs, and tests/ checks them with `sh -n`.

// args: (config, dir) pairs. One line per call: `<kind>\t<config>\t<json on one line>`. The last line of
// a project is `warn`: why mise printed nothing (untrusted config, tools missing from the lockfile) or "".
var project = [
    'while [ $# -gt 1 ]; do f=$1; d=$2; shift 2; e=$(mktemp)',
    'for k in ls outdated bump; do',
    'case $k in ls) a="ls --json";; outdated) a="outdated --json";; bump) a="outdated --bump --json";; esac',
    'printf "%s\\t%s\\t" "$k" "$f"; mise -C "$d" $a 2>>"$e" | tr -d "\\n"; printf "\\n"',
    'done',
    'w=; grep -q "not trusted" "$e" && w=untrusted || { grep -q "not in the lockfile" "$e" && w=unlocked; }',
    'printf "warn\\t%s\\t\\"%s\\"\\n" "$f" "$w"; rm -f "$e"',
    'done'
].join("\n");

// first line: $HOME; then every tracked config file that still exists
var tracked = [
    'd="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/tracked-configs"',
    'echo "$HOME"',
    'for f in "$d"/*; do [ -L "$f" ] || continue; p=$(readlink -f "$f") && [ -f "$p" ] && echo "$p"; done'
].join("\n");

// arg: folder or file -> absolute config file path; error text on stderr
var resolve = [
    'p=$1',
    'case "$p" in "~"|"~/"*) p="$HOME${p#"~"}";; esac',
    'g="${MISE_GLOBAL_CONFIG_FILE:-$HOME/.config/mise/config.toml}"',
    'ok() { r=$(readlink -f "$1"); [ "$r" = "$(readlink -f "$g")" ] && { echo "That is the global config" >&2; exit 1; }; echo "$r"; exit 0; }',
    '[ -f "$p" ] && ok "$p"',
    '[ -d "$p" ] || { echo "Not found: $1" >&2; exit 1; }',
    'for c in mise.toml .mise.toml mise/config.toml .mise/config.toml .config/mise.toml .config/mise/config.toml; do [ -f "$p/$c" ] && ok "$p/$c"; done',
    'echo "No mise config in $1" >&2; exit 1'
].join("\n");

// args: ("untrusted" | "unlocked", config, dir) triples ("" = global): `mise trust` the config, or `mise lock`
// (`-g` for global). One failing does not stop the others (it would stay first in line and block them); the
// job fails at the end.
var fix = [
    'rc=0',
    'while [ $# -gt 2 ]; do k=$1; f=$2; d=$3; shift 3',
    'if [ "$k" = untrusted ]; then mise trust "$f"; elif [ -n "$f" ]; then mise -C "$d" lock; else mise lock -g; fi || rc=1',
    'done',
    'exit $rc'
].join("\n");

// args: project dir ("" = global), tool. Under `locked = true`, `use` of a version that is already
// installed (another scope has it) needs no download: it writes the config, exits 0 and leaves the
// lockfile without the entry. Lock it, but only when `locked` is on: `mise lock` would create a
// lockfile nobody asked for.
var lockAfterUse = [
    'd=${1:-$HOME}; [ "$(mise -C "$d" settings get locked 2>/dev/null)" = true ] || exit 0',
    'if [ -n "$1" ]; then mise -C "$1" lock "$2"; else mise lock -g "$2"; fi'
].join("\n");

// arg: tool. Uninstall every installed version of a tool that no tracked config declares. `mise unuse` removes
// the tool from the config but leaves its entries in mise.lock, and `mise prune` counts a lockfile as a
// requirement, so the version would stay. Without touching any of the user's mise settings, do what the user
// asked (remove it) with `mise uninstall`, after the check `prune` would have made: a tracked config (read as
// text, so a project that is no longer trusted still counts) that declares the tool as a key (`name =`,
// `"backend:name" =`, `[tools.name]`) keeps it, and the script says so (`kept: <that config>`, which the toast
// shows) instead of staying silent. Nothing installed is not an error.
var uninstallUndeclared = [
    'd="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/tracked-configs"',
    'e=$(printf %s "$1" | sed \'s/[][\\.*^$(){}+?|]/\\\\&/g\')',
    'for f in "$d"/*; do [ -L "$f" ] || continue; p=$(readlink -f "$f") && [ -f "$p" ] || continue',
    'if grep -Eq "^[[:space:]]*(\\"$e\\"|$e)[[:space:]]*=|^[[:space:]]*\\[tools\\.(\\"$e\\"|$e)\\]" "$p"; then',
    'o=$(readlink "$f"); case "$o" in "$HOME"/*) o="~${o#"$HOME"}";; esac; echo "kept: $o"; exit 0',
    'fi',
    'done',
    'exec mise uninstall --yes --all "$1"'
].join("\n");

// args: config file ("" = global), project dir, tool, version.
// With `locked = true` mise refuses `use` for a tool the lockfile lacks. What the user would do by
// hand: write the tool into the config, lock it, install it. `config set` only writes a plain
// `name = "version"`, so tools with [options] or a dotted name (it would split the key) are left out
// by lockedInstall and fail with failureSummary's hint. One the config declares with options (a table
// or a list) is refused by the script itself, reading the toml: `config set` would overwrite them,
// while a plain version is rewritten, as `mise use` does. `config set` makes a paranoid config
// untrusted (its hash changed): if the file loaded before our edit and no longer does, it is trusted
// again, like mise does for its own rewrites. One that did not load before stays as it is.
var locked = [
    'f=$1; [ -n "$f" ] || f=${MISE_GLOBAL_CONFIG_FILE:-$HOME/.config/mise/config.toml}',
    'v=$(mise config get -f "$f" "tools.$3" 2>/dev/null) && case "$v" in *=*|"["*) echo "ERROR: $3 has options in $f: change it there by hand" >&2; exit 1;; esac',
    'if [ -n "$1" ]; then',
    'mise -C "$2" ls --json >/dev/null 2>&1 && t=1',
    'mise config set -f "$1" "tools.$3" "$4" && { mise -C "$2" ls --json >/dev/null 2>&1 || [ -z "$t" ] || mise trust "$1"; } && mise -C "$2" lock "$3" && mise -C "$2" install --yes "$3"',
    'else',
    'mise config set -f "$f" "tools.$3" "$4" && mise lock -g "$3" && mise install --yes "$3"',
    'fi'
].join("\n");
