#!/usr/bin/env bash
# Offline tests for the template-owned image logic that has no other check:
# the Makefile's repo derivation, check-dockerfile-versions.sh, image-smoke.sh's
# missing-tar failure and skopeo.sh's argument handling. Needs no Docker daemon
# (docker is stubbed) and writes only to a temp directory. Run by the
# `image-scripts-test` hook.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

fail() {
    echo "FAIL: $*" >&2
    failures=$((failures + 1))
}

# expect_eq NAME EXPECTED ACTUAL
expect_eq() {
    [[ "$2" == "$3" ]] || fail "$1: expected '$2', got '$3'"
}

# Makefile: REPO from the origin remote, in every URL form we claim to parse.
repo_of() {
    local dir="$tmp/repo-$RANDOM"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$1"
    (cd "$dir" && env -u GITHUB_REPOSITORY make -s -f "$root/Makefile" \
        -f <(printf 'show-repo:\n\t@echo $(REPO)\n') show-repo)
}
while IFS='|' read -r url want; do
    expect_eq "repo from $url" "$want" "$(repo_of "$url")"
done <<'EOF_URLS'
https://github.com/o/r.git|o/r
https://github.com/o/r|o/r
https://user:token@github.com/o/r.git/|o/r
git@github.com:o/r.git|o/r
ssh://git@github.com/o/r.git|o/r
ssh://git@github.com:22/o/r.git|o/r
ssh://git@ssh.github.com:443/o/r|o/r
ssh://github.com:2222/o/r.git|o/r
git+ssh://git@host:22/o/r.git|o/r
SSH://git@host:22/o/r.git|o/r
EOF_URLS

# check-dockerfile-versions.sh in a scratch repo layout.
dv="$tmp/dv"
mkdir -p "$dv/.devcontainer"
run_dv() { (cd "$dv" && bash "$root/scripts/check-dockerfile-versions.sh" "$@" 2>&1); }
printf 'ARG A=1\nARG B="x" # c\nFROM scratch\nARG A\n' >"$dv/.devcontainer/Dockerfile"
printf 'ARG A\nARG A=1\nARG B=x\nFROM scratch\nARG A=1\n' >"$dv/Dockerfile"
run_dv A B >/dev/null || fail "check-dockerfile-versions: matching ARGs (bare re-declaration first) should pass"
printf 'ARG A=1\nFROM scratch\nARG A=2\n' >"$dv/Dockerfile"
out="$(run_dv A)" && fail "check-dockerfile-versions: conflicting defaults in one file should fail"
[[ "$out" == *"conflicting defaults"* ]] || fail "check-dockerfile-versions: wrong message: $out"
printf 'ARG A=2\n' >"$dv/Dockerfile"
out="$(run_dv A)" && fail "check-dockerfile-versions: mismatch should fail"
[[ "$out" == *"mismatch"* ]] || fail "check-dockerfile-versions: wrong message: $out"
printf 'ARG A\n' >"$dv/Dockerfile"
run_dv A >/dev/null && fail "check-dockerfile-versions: no default should fail"
printf 'ARG B=1\n' >"$dv/Dockerfile"
run_dv A >/dev/null && fail "check-dockerfile-versions: missing ARG should fail"

# image-smoke.sh must fail when the tar for the arch under test is missing.
case "$(uname -m)" in
    aarch64 | arm64) host=arm64 other=amd64 ;;
    *) host=amd64 other=arm64 ;;
esac
mkdir -p "$tmp/dist"
smoke() {
    env IMAGE_TAR_PREFIX="$tmp/dist/app-1.0.0" SKOPEO_IMAGE=unused RELEASE_VERSION=1.0.0 "$@" \
        bash "$root/scripts/image-smoke.sh" 2>&1
}
out="$(smoke RELEASE_ARCH="$host")" && fail "image-smoke: missing tar with RELEASE_ARCH should fail"
[[ "$out" == *"not found"* ]] || fail "image-smoke: wrong message: $out"
out="$(smoke ARCHES="$host")" && fail "image-smoke: missing host-arch tar should fail"
[[ "$out" == *"not found"* ]] || fail "image-smoke: wrong message: $out"
smoke ARCHES="$other" >/dev/null || fail "image-smoke: host arch not built by the instance should skip"

# skopeo.sh: no extra docker args (empty array under set -u) and with some.
mkdir -p "$tmp/bin" "$tmp/dist-s"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*"\n' >"$tmp/bin/docker"
chmod +x "$tmp/bin/docker"
sk() { PATH="$tmp/bin:$PATH" SKOPEO_IMAGE=img SKOPEO_DIST_DIR="$tmp/dist-s" bash "$root/scripts/skopeo.sh" "$@"; }
out="$(sk -- copy a b)" || fail "skopeo.sh: no docker args should work"
[[ "$out" == *"img copy a b" ]] || fail "skopeo.sh: unexpected command: $out"
out="$(sk -i -- login)" || fail "skopeo.sh: docker args should work"
[[ "$out" == *" -i img login" ]] || fail "skopeo.sh: unexpected command: $out"

if [[ $failures -ne 0 ]]; then
    echo "$failures failure(s)" >&2
    exit 1
fi
echo "image scripts: all tests passed"
