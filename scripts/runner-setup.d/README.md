# scripts/runner-setup.d/

Instance hook directory for the runner stage of the top-level
`Dockerfile`. `../runner-setup.sh` (template-owned, `replace` tier) creates
the group-0 runtime user and makes `/app` and the home directory
group-writable, then runs every `*.sh` here in glob order as
`bash NN-name.sh APP_UID`, still as root, in the same `RUN` layer.

Empty apart from this file in the template. An instance adds files such as
`10-ca-certificates.sh` (install extra packages, create extra writable
directories) instead of editing `runner-setup.sh`.

## Do

- Number files (`NN-name.sh`) so the order is explicit.
- Use `set -euo pipefail` and give any extra directory the same group-0
  ownership and `g+rwX` mode `runner-setup.sh` gives `/app`.

## Don't

- Edit `../runner-setup.sh`; a template sync overwrites it.
- Put build-stage steps here; this runs in the `runner` stage only.
