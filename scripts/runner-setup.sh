#!/usr/bin/env bash
# Prepares the runner stage's runtime user for arbitrary-UID platforms
# (e.g. OpenShift, which ignores an image's own UID and always runs it
# under group 0): group-0 ownership plus group read/write/execute on
# every directory the app needs, and a numeric (not named) final USER in
# the Dockerfile. Large trees (a venv, node_modules) get the equivalent
# via COPY --chown/--chmod instead of a recursive chmod here, which would
# be slow.
#
# Usage: runner-setup.sh APP_UID
#
# Afterwards runs every runner-setup.d/*.sh next to this script, in glob
# order, as `bash NN-name.sh APP_UID`; see runner-setup.d/README.md.
set -euo pipefail

app_uid=$1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /app
useradd --create-home --uid "$app_uid" --gid 0 appuser

chgrp -R 0 /app /home/appuser
chmod -R g+rwX /app /home/appuser

shopt -s nullglob
for hook in "$here"/runner-setup.d/*.sh; do
    bash "$hook" "$app_uid"
done
