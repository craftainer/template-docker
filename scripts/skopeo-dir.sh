#!/usr/bin/env bash
# Prints the path of a new temporary directory that skopeo.sh's container can
# write to, with the least permission that works. skopeo.sh runs the container
# as the caller's uid:gid, so a plain `mktemp -d` (0700, owned by the caller)
# is enough on a rootful daemon. Under rootless or userns-remapped Docker the
# container's uid maps to a subordinate uid that is not the owner, so the
# directory has to be 0777 there (a known residual on shared hosts: it is
# short-lived and the caller removes it).
#
# Usage: skopeo-dir.sh [MKTEMP_TEMPLATE]
set -euo pipefail

dir="$(mktemp -d "${1:-${TMPDIR:-/tmp}/skopeo.XXXXXX}")"

# SecurityOptions lists e.g. "name=seccomp,profile=builtin name=rootless";
# an unreachable daemon or a missing format field falls through to 0700.
opts="$(docker info --format '{{range .SecurityOptions}}{{.}} {{end}}' 2>/dev/null || true)"
case "$opts" in
    *name=rootless* | *name=userns*) chmod 0777 "$dir" ;;
esac

printf '%s\n' "$dir"
