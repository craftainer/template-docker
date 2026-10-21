#!/usr/bin/env bash
# Loads the release image tar that `make build` left in dist/, runs it and
# polls a URL until it answers 2xx. Always removes the container; prints its
# logs on failure.
#
# Usage: image-smoke.sh   (configured by environment; `make image-smoke`
# sets these)
#   IMAGE_TAR_PREFIX     required; tar is "$IMAGE_TAR_PREFIX-<arch>.tar"
#                        (e.g. dist/template-docker-1.2.3)
#   RELEASE_VERSION      if that tar is missing (the image name may differ
#                        when the repository name can't be derived), the one
#                        dist/*-$RELEASE_VERSION-<arch>.tar is used instead
#   RELEASE_ARCH         arch to test; default: the host's, else amd64
#   IMAGE_SMOKE_PORT     container port (default 8000)
#   IMAGE_SMOKE_PATH     URL path (default /health/live)
#   IMAGE_SMOKE_RUN_ARGS extra `docker run` words, whitespace-separated and
#                        without embedded spaces or quotes, e.g. "-e FOO=bar"
#                        (read from the environment, never from recipe text)
#   IMAGE_SMOKE_TIMEOUT  seconds to wait (default 60)
set -euo pipefail

prefix="${IMAGE_TAR_PREFIX:?IMAGE_TAR_PREFIX is required}"
port="${IMAGE_SMOKE_PORT:-8000}"
path="${IMAGE_SMOKE_PATH:-/health/live}"
timeout="${IMAGE_SMOKE_TIMEOUT:-60}"
read -r -a run_args <<<"${IMAGE_SMOKE_RUN_ARGS:-}"

case "$(uname -m)" in
    aarch64 | arm64) host_arch=arm64 ;;
    *) host_arch=amd64 ;;
esac
arch="${RELEASE_ARCH:-$host_arch}"
if [[ -z "${RELEASE_ARCH:-}" && ! -f "$prefix-$arch.tar" ]]; then
    arch=amd64
fi
tar="$prefix-$arch.tar"
if [[ ! -f "$tar" && -n "${RELEASE_VERSION:-}" ]]; then
    shopt -s nullglob
    candidates=("$(dirname "$prefix")"/*-"$RELEASE_VERSION-$arch".tar)
    if [[ ${#candidates[@]} -eq 1 ]]; then
        tar="${candidates[0]}"
    fi
fi
[[ -f "$tar" ]] || { echo "image-smoke: $tar not found; run 'make build' first." >&2; exit 1; }

echo "image-smoke: loading $tar"
loaded="$(docker load -i "$tar")"
echo "$loaded"
image="${loaded##*: }"

cid=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
    status=$?
    if [[ -n "$cid" ]]; then
        if [[ $status -ne 0 ]]; then
            echo "image-smoke: container logs:" >&2
            docker logs "$cid" >&2 || true
        fi
        docker rm -f "$cid" >/dev/null 2>&1 || true
    fi
    docker image rm -f "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cid="$(docker run -d -p "127.0.0.1::${port}" "${run_args[@]}" "$image")"
mapped="$(docker port "$cid" "${port}/tcp" | head -n1 | sed 's/.*://')"
url="http://127.0.0.1:${mapped}${path}"

echo "image-smoke: waiting up to ${timeout}s for $url"
deadline=$((SECONDS + timeout))
while ((SECONDS < deadline)); do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$cid")" != "true" ]]; then
        echo "image-smoke: container exited before answering" >&2
        exit 1
    fi
    if curl -fsS -o /dev/null "$url" 2>/dev/null; then
        echo "image-smoke: $url answered 2xx"
        exit 0
    fi
    sleep 1
done
echo "image-smoke: timed out after ${timeout}s waiting for $url" >&2
exit 1
