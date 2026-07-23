# kamino-config

A **demo configuration repository** for [Kamino](https://github.com/t0mer/kamino),
the single-binary Ubuntu server provisioner. Point Kamino at this repo (or fork
it and edit) and it will show you everything below as an installable plan and run
it, streaming live progress.

Kamino ships with **no** configuration baked in — it fetches whatever repo you
point it at over HTTPS as raw content (no git clone), pins it to a commit SHA for
the run, and treats it as read-only truth. This repo is a worked example of that
contract.

## Use it with Kamino

```bash
# Validate this repo's schema, dependency graph and per-arch source coverage:
kamino validate --repo https://github.com/t0mer/kamino-config

# See the resolved, ordered plan for a profile:
kamino plan --repo https://github.com/t0mer/kamino-config --profile production

# Install it (headless) — or run `kamino serve` and drive it from the web UI:
sudo kamino apply --repo https://github.com/t0mer/kamino-config --profile dev --yes
```

## What's in this demo

Four categories:

| Category | Items |
|---|---|
| **dev** | Go (tarball), Python 3.12 (apt), base PyPI packages (pip), uv (script) |
| **tools** | jq, ripgrep, htop (apt), yq (binary), a login banner (script, from `scripts/`) |
| **containers** | Docker Engine (script), Docker Compose plugin (apt), ctop (binary), Prometheus + Grafana monitoring stack (compose_stack) |
| **network** | Cloudflare Tunnel (deb, with a `CF_TUNNEL_TOKEN` secret), Tailscale (script) |

Three profiles:

| Profile | Selection |
|---|---|
| **production** | all tools + containers + Cloudflare Tunnel; excludes `dev/*` |
| **dev** | all dev + tools + Docker & Compose; pins Go to `1.23.4` via an override |
| **minimal** | jq, ripgrep, htop only |

Between them the demo exercises every runner Kamino supports — `apt`, `deb`,
`tarball`, `binary`, `pip`, `script`, and `compose_stack` — plus dependency
ordering, per-arch sources, version overrides, secrets, and a compose stack.

## Repository layout

```
kamino-config/
├── manifest.yaml            # entry point: schema version, defaults, category & profile index
├── categories/              # installable items grouped by category
│   ├── dev.yaml
│   ├── tools.yaml
│   ├── containers.yaml
│   └── network.yaml
├── profiles/                # named selections of items, with optional version overrides
│   ├── production.yaml
│   ├── dev.yaml
│   └── minimal.yaml
├── scripts/                 # shell scripts referenced by script items (source: scripts/…)
│   └── setup-motd.sh
└── stacks/                  # docker-compose stacks referenced by compose_stack items
    └── monitoring/
        ├── docker-compose.yaml
        └── prometheus.yml
```

## Schema reference

The authoritative JSON Schema lives in the app repo under
[`schema/`](https://github.com/t0mer/kamino/tree/main/schema)
(`manifest.schema.json`, `category.schema.json`, `profile.schema.json`).

### `manifest.yaml`

```yaml
schema: 1                      # required, must be 1
name: kamino-demo              # required
defaults:
  apt_update_before_run: true  # run one `apt-get update` at the start of a run
  timeout: 15m                 # per-step default (^[0-9]+[smh]$)
categories:                    # required: paths to category files
  - categories/dev.yaml
profiles:                      # paths to profile files
  - profiles/production.yaml
```

### Category items

Each category file has `id`, `name`, optional `order`, and a list of `items`.
Common item fields:

| Field | Meaning |
|---|---|
| `id`, `name`, `type` | required; `type` ∈ `apt`, `deb`, `tarball`, `binary`, `pip`, `script`, `compose_stack`, `snap` |
| `version` | version string; `{version}` is templated into `source`, `check`, etc. |
| `source` | download URL — a string, or a per-arch `{amd64, arm64}` map (must be `https://`). A `script` item may instead give a repo-relative path (e.g. `scripts/foo.sh`), fetched from the config repo at run time |
| `sha256` | expected digest (string or per-arch map); verified before install. **Absent → the plan warns and the download is unverified** |
| `packages` | apt/pip package list |
| `repo` | apt repo/PPA to add first |
| `python` | interpreter for `pip` items |
| `install_dir`, `path_export` | tarball extraction dir and `PATH` addition |
| `path`, `files`, `env_file` | `compose_stack`: repo directory, files to materialise, secret-env marker |
| `depends_on` | list of `category/item` refs (drives topological ordering) |
| `check` + `check_contains` | idempotency probe — if `check`'s output contains `check_contains`, the step is **skipped** |
| `pre_install` / `post_install` | shell lines run before/after |
| `timeout`, `arch`, `secrets` | per-step timeout, arch restriction (`[amd64]`/`[arm64]`), and names of secret values the UI/CLI must supply |

### Profiles

```yaml
id: dev
name: Developer Workstation
include: [ "dev/*", "tools/*", "containers/docker" ]   # globs or exact refs
exclude: [ "dev/uv" ]
overrides:
  dev/go: { version: "1.23.4" }                        # pin/override a version
```

### Secrets

Values like `CF_TUNNEL_TOKEN` or `GRAFANA_ADMIN_PASSWORD` are **declared by name**
here, never by value. Kamino prompts for them at run time (UI or `--secret
KEY=VALUE`), holds them in memory only, injects them via `{secret:NAME}`
templating (and `${NAME}` env for compose stacks), redacts them from logs, and
never writes them to disk.

> The `sha256` fields are intentionally omitted in this demo, so a real run is
> possible without hard-coding digests — Kamino warns for each. For a hardened
> config, add the real per-arch digests so every download is verified.

## CI validation

`.github/workflows/validate.yml` validates this repo on every push and PR by
building Kamino and running `kamino validate` against the checkout, so a bad
manifest, a dependency cycle, a missing ref, or an arch without a source is
caught before anyone deploys it.

## License

[Apache-2.0](LICENSE).
