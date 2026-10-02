# Shared helpers for scripts/*.sh. Source it; don't run it.
#
#   ROOT                      repo root
#   UPSTREAM_REF              Bellard's last C mquickjs commit before the port (7ea5399)
#   build_port                aeb-build this checkout; sets PORT_MQJS / PORT_EXAMPLE
#   build_ref <commit>        build <commit> in a git worktree under
#                             target/ref/<commit>; sets REF_MQJS / REF_EXAMPLE.
#                             Upstream C commits build with their own Makefile,
#                             port commits with aeb.
#   fetch_extras              download + verify Bellard's mquickjs-extras
#                             (dtoa/libm tests, Octane) into target/extras;
#                             sets EXTRAS

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM_REF=${UPSTREAM_REF:-7ea5399}
# The Aether source tree the engine builds against. Not called AETHER: aeb
# reads $AETHER as the path to the `ae` binary.
AETHER_TREE=${MQJS_AETHER_HOME:-${AETHER_TREE:-/home/paul/scm/aether}}

EXTRAS_URL=https://bellard.org/mquickjs/mquickjs-extras.tar.xz
EXTRAS_SHA256=9af5cc3794831ad7c65d07bfec9babbde24b952c6c1c1702bc766545bccbb131

die() { echo "$(basename "$0"): $*" >&2; exit 1; }

# aeb's orchestrator needs Aether >= 0.758 on PATH; the engine itself builds
# against the dev tree named by MQJS_AETHER_HOME (see AGENTS.md).
aeb_env() {
    unset AETHER                       # aeb would take it as the ae binary
    export AETHER_HOME="$AETHER_TREE"
    export MQJS_AETHER_HOME="$AETHER_TREE"
    export PATH="$AETHER_TREE/build:$PATH"
}

build_port() {
    aeb_env
    (cd "$ROOT" && aeb .build.ae >/dev/null && aeb example-app/.build.ae >/dev/null) \
        || die "aeb build of this checkout failed (run 'aeb .build.ae' to see why)"
    PORT_MQJS="$ROOT/target/build/bin/mqjs"
    PORT_EXAMPLE="$ROOT/target/build/example-app/bin/example"
}

build_ref() {
    ref=$1
    sha=$(git -C "$ROOT" rev-parse --short=12 "$ref^{commit}") \
        || die "unknown commit: $ref"
    wt="$ROOT/target/ref/$sha"
    if [ ! -d "$wt" ]; then
        mkdir -p "$ROOT/target/ref"
        git -C "$ROOT" worktree add --detach -q "$wt" "$sha" \
            || die "git worktree add failed for $sha"
    fi
    if [ -f "$wt/mquickjs.c" ]; then
        # Bellard's C tree: its own Makefile
        if [ ! -x "$wt/mqjs" ] || [ ! -x "$wt/example" ]; then
            make -C "$wt" -j"$(nproc 2>/dev/null || echo 4)" mqjs example >"$wt/.build.log" 2>&1 \
                || die "make failed in $wt (see $wt/.build.log)"
        fi
        REF_MQJS="$wt/mqjs"
        REF_EXAMPLE="$wt/example"
    else
        # a port commit: aeb (needs a commit new enough for today's aeb)
        aeb_env
        if [ ! -x "$wt/target/build/bin/mqjs" ]; then
            (cd "$wt" && aeb .build.ae && aeb example-app/.build.ae) >"$wt/.build.log" 2>&1 \
                || die "aeb build failed in $wt (see $wt/.build.log)"
        fi
        REF_MQJS="$wt/target/build/bin/mqjs"
        REF_EXAMPLE="$wt/target/build/example-app/bin/example"
    fi
    REF_SHA=$sha
}

# Remove every worktree build_ref created.
clean_refs() {
    for wt in "$ROOT"/target/ref/*; do
        [ -d "$wt" ] && git -C "$ROOT" worktree remove --force "$wt"
    done
    git -C "$ROOT" worktree prune
}

fetch_extras() {
    EXTRAS="$ROOT/target/extras"
    if [ ! -f "$EXTRAS/.ok" ]; then
        mkdir -p "$EXTRAS"
        tarball="$EXTRAS/mquickjs-extras.tar.xz"
        curl -sSfL -o "$tarball" "$EXTRAS_URL" || die "download failed: $EXTRAS_URL"
        echo "$EXTRAS_SHA256  $tarball" | sha256sum -c --quiet - \
            || die "checksum mismatch for $EXTRAS_URL (upstream changed? update EXTRAS_SHA256)"
        tar -xJf "$tarball" -C "$EXTRAS" || die "extract failed"
        touch "$EXTRAS/.ok"
    fi
}
