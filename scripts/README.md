# scripts/

- `develop.sh` — `../.devcontainer/Dockerfile`'s `develop`-stage setup: installs `prek`,
  the Claude Code CLI, `snip` and the GitHub CLI (`gh`), the only tooling this template requires
  regardless of instance language. An instance adds its own language
  runtime/tooling install on top, either by extending this script or
  copying its shape into a second script. Prefer the hook below over
  either.
- `post-create.sh` — the devcontainer's `postCreateCommand`: git
  `safe.directory`, `prek install`, then every `post-create.d/*.sh`.
- `develop.d/`, `post-create.d/`, `runner-setup.d/` — instance hook
  directories, empty apart from their own `README.md`; see
  `docs/TEMPLATE.md`'s "Instance extension points".
- `runner-setup.sh` — the top-level `Dockerfile`'s `runner` stage setup:
  group-0 runtime user for arbitrary-UID platforms, then every
  `runner-setup.d/*.sh`.
- `image-smoke.sh` — `make image-smoke` (a `release-check` prerequisite):
  loads the release image tar from `dist/`, runs it and polls
  `IMAGE_SMOKE_PATH` until 2xx; usage in the script's header.
- `check-dockerfile-versions.sh ARG...` — fails when a named `ARG` default
  differs between `.devcontainer/Dockerfile` and the top-level `Dockerfile`.

## Do

- Keep this script's own tools pinned to an exact version (a `# renovate:`
  ARG in `../.devcontainer/Dockerfile`) and checksum-verified where the upstream project
  publishes checksums, matching the pattern each install step here already
  follows.

## Don't

- Add a language runtime or stack-specific tool here — that belongs in the
  instance's own layer (`develop.d/`), not the base template's.
