#!/usr/bin/env bash
# GOSSIP-0.3 acceptance — Phase 0 (library build).
#
# Pins the three Phase 0 acceptance items from plans/cajeta-gossip-plan.md:
#   1. `cajeta build` in this repo emits a library artifact (no entry method):
#      build/archive/dev.cajeta.gossip-<version>.cja
#   2. A throwaway consumer project resolves + links cajeta-gossip as a dep
#      and its binary runs against the library's API. (Via a filesystem
#      repository — the direct-dep route the 0.9.2 resolver implements;
#      `{ "path": ... }` overrides apply only to transitive deps, and the
#      spec'd path-dependency *source* form is Phase 6c, not landed.)
#   3. The library manifest declares no entry-method (the library signal).
#
# Usage: test/phase0.sh   (from anywhere; locates the repo from its own path)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="${TMPDIR:-/tmp}/gossip-phase0-$$"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok: $*"; }

echo "== Phase 0 acceptance (repo: $repo) =="

# --- 3. manifest exists and is a *library* manifest (no entry-method) ---
[[ -f "$repo/cajeta.json" ]] || fail "no cajeta.json in repo root"
grep -q '"entry-method"' "$repo/cajeta.json" \
  && fail "cajeta.json declares entry-method — that makes it a binary, not a library"
grep -q '"dev.cajeta.gossip"' "$repo/cajeta.json" \
  || fail "cajeta.json details.name is not dev.cajeta.gossip"
pass "library manifest present, no entry-method"

# --- 1. cajeta build emits the .cja archive ---
version=$(sed -n 's/.*"version": *"\([0-9][^"]*\)".*/\1/p' "$repo/cajeta.json" | head -1)
[[ -n "$version" ]] || fail "could not read details.version from cajeta.json"
(cd "$repo" && cajeta build) || fail "cajeta build failed in repo root"
cja="$repo/build/archive/dev.cajeta.gossip-$version.cja"
[[ -f "$cja" ]] || fail "expected library artifact not found: $cja"
pass "cajeta build emitted $(basename "$cja")"

# --- 2. throwaway consumer links the library as a dependency ---
# Stage the built .cja into a filesystem-repository layout:
#   <root>/<name>/<version>/<name>-<version>.cja  (+ sidecar cajeta.json)
fsrepo="$work/fsrepo"
mkdir -p "$fsrepo/dev.cajeta.gossip/$version"
cp "$cja" "$fsrepo/dev.cajeta.gossip/$version/"
cp "$repo/cajeta.json" "$fsrepo/dev.cajeta.gossip/$version/cajeta.json"
pass "staged $(basename "$cja") into filesystem repo layout"

consumer="$work/consumer"
mkdir -p "$consumer/src/main/cajeta/probe"
cat > "$consumer/cajeta.json" <<EOF
{
    "details": {
        "name":                "probe.consumer",
        "version":             "0.0.1",
        "description":         "throwaway consumer for the phase0 acceptance test",
        "license":             "Apache-2.0",
        "authors":             ["test"],
        "cajeta-lang-version": "1.0"
    },
    "settings": {
        "capabilities": ["network"],
        "dependencies": {
            "dev.cajeta.gossip": "$version"
        },
        "repositories": [
            { "name": "local-stage", "type": "filesystem",
              "path": "$fsrepo", "priority": 100 }
        ],
        "build": {
            "target":       "host",
            "entry-method": "probe.Main::main"
        }
    },
    "tasks": {
        "build": {
            "description": "consumer binary",
            "actions": [
                { "action": "build", "flavor": "debug",
                  "output-path": "build/probe", "id": "art" }
            ],
            "outputs": { "path": "\${art.path}", "sha256": "\${art.sha256}" }
        }
    }
}
EOF
cat > "$consumer/src/main/cajeta/probe/Main.cajeta" <<'EOF'
package probe;

import dev.cajeta.gossip.MemberState;
import dev.cajeta.gossip.EventKind;

public class Main {
    public static void main(String[] args) {
        MemberState s = MemberState.ALIVE;
        EventKind k = EventKind.JOINED;
        if (s == MemberState.ALIVE && k == EventKind.JOINED) {
            System.stdout.println("gossip-linked");
        }
    }
}
EOF

if (cd "$consumer" && cajeta build) && [[ -x "$consumer/build/probe" ]]; then
    out="$("$consumer/build/probe")"
    [[ "$out" == *"gossip-linked"* ]] || fail "consumer binary ran but output wrong: $out"
    pass "consumer resolved dev.cajeta.gossip from the filesystem repo, linked, and ran: $out"
else
    fail "consumer project failed to resolve/link dev.cajeta.gossip from the filesystem repository"
fi

echo "== Phase 0 acceptance: ALL PASS =="
