#!/usr/bin/env bash
# Usage: check-dockerfile-versions.sh ARG [ARG...]
#
# Each named ARG must be declared (`ARG NAME=value`) with the same default
# in both the base-owned .devcontainer/Dockerfile (develop stage) and the
# top-level Dockerfile (builder/runner stages): the runtime image must match
# the toolchain the devcontainer tests against. Exits 1 if one differs or
# is missing from either file. ARGs not named are not checked.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "usage: $0 ARG [ARG...]" >&2
    exit 2
fi

status=0
for arg in "$@"; do
    dev="$(grep -m1 "^ARG ${arg}=" .devcontainer/Dockerfile | cut -d= -f2- || true)"
    app="$(grep -m1 "^ARG ${arg}=" Dockerfile | cut -d= -f2- || true)"
    if [[ -z "$dev" || -z "$app" ]]; then
        echo "${arg} missing: .devcontainer/Dockerfile has '${dev}', Dockerfile has '${app}'" >&2
        status=1
    elif [[ "$dev" != "$app" ]]; then
        echo "${arg} mismatch: .devcontainer/Dockerfile has '${dev}', Dockerfile has '${app}'" >&2
        status=1
    fi
done
exit "$status"
