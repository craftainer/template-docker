# 0002. Run the ZAP baseline scan as the image's passive DAST

## Status

Accepted

## Context

The permanent scanners the org chose for the OWASP Top Ten (2025) cover
source (CodeQL), workflows (zizmor), secrets (gitleaks) and dependencies
(osv-scanner, Trivy on the image). Nothing looks at the running image, so
missing security headers, cookie flags and information leaks (A02, A07)
go unseen. `template-docker` already starts the image in `image-smoke.sh`
and owns the image hooks, so it is the one place to add this for every app
template.

Active scanning (attack payloads) against a container started in CI or a
developer's devcontainer would need an app-specific setup (authentication,
seed data, a throwaway database) that a generic image layer cannot know.

## Decision

We will run the ZAP baseline scan (`zap-baseline.py`) as the manual-stage
`image-dast` hook, in `scripts/image-dast.sh`.

- **Scanner.** The official ZAP image, pinned by tag and digest
  (`ghcr.io/zaproxy/zaproxy:<version>@sha256:…`), as `scripts/image-scan.sh` does for Trivy.
  A Renovate regex manager keeps both current.
- **Passive only.** The baseline scan spiders the app for a minute and
  applies only passive rules; it sends no attack traffic. Active scans are
  out of scope for the template; an instance may add its own.
- **Same start-up as the smoke test.** The script loads the release tar
  with skopeo and runs it with the same `IMAGE_SMOKE_*` settings, then runs
  ZAP in the app container's network namespace
  (`--network container:<id>`), so nothing extra is exposed on the host
  network.
- **Exit codes.** `zap-baseline.py` exits 0 (clean), 2 (warnings only),
  1 (a rule at FAIL) or 3 (other failure). 0 and 2 pass; 1 and 3 fail. The
  script does not pass `-I`, which would turn FAIL into a pass too.
- **Instance-owned rule levels.** `.zap/rules.tsv` (`ignore` tier) holds the
  instance's `IGNORE|WARN|FAIL` lines, seeded with a commented header and
  no blanket IGNOREs. A rule not listed is a WARN: reported, not failing.
  An instance promotes the rules it wants enforced to FAIL.

## Consequences

- Header, cookie and leak regressions in the running image can be found
  before release, without app-specific setup.
- Findings are warnings until an instance promotes them, so a fresh
  instance passes; enforcement is a per-instance decision.
- The scan needs Docker, the built tar and a pull of the ZAP image, and
  adds about the spider time (one minute by default) plus ZAP's start-up to
  a run; hence the manual stage, not `pre-commit`.
- Passive scanning cannot find injection or authorization flaws; CodeQL and
  review remain responsible for those.
- The script repeats the load-and-run steps of `image-smoke.sh` rather than
  sharing them, because the smoke script removes its container on exit.
  Changes to how the smoke test starts the image must be mirrored.
