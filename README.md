# kamino-config

A **demo configuration repository** for [Kamino](https://github.com/t0mer/kamino),
the single-binary Ubuntu server provisioner. Point Kamino at this repo (or fork
it and edit it), and Kamino shows everything below as an installable plan, runs
it, and streams live progress.

Kamino ships with **no** configuration baked in. It fetches whatever repo you
point it at over HTTPS as raw files (no git clone) and treats that repo as
read-only truth. For repos on `github.com` or `gitlab.com` (this one included)
it pins the branch or tag to a commit SHA for the run, so a push in the middle
of a run can't change the plan. This repo is a worked example of that contract:
four categories, three profiles, a local script and a Docker Compose stack.

> **Heads-up:** everything in a config repo runs **as root** on the target
> server. Read [Security notes](#security-notes) before you point a real machine
> at this demo or at your fork of it.

## Contents

- [Use it with Kamino](#use-it-with-kamino)
- [What's in this demo](#whats-in-this-demo)
  - [Categories and items](#categories-and-items)
  - [Profiles](#profiles)
  - [The `motd` script](#the-motd-script)
  - [The monitoring stack](#the-monitoring-stack)
- [Repository layout](#repository-layout)
- [Schema reference](#schema-reference)
- [Customizing and forking](#customizing-and-forking)
- [Validation and CI](#validation-and-ci)
- [Security notes](#security-notes)
- [License](#license)

## Use it with Kamino

Kamino runs on Ubuntu (`amd64` or `arm64`). Get the binary from the
[Kamino releases](https://github.com/t0mer/kamino/releases) and see the
[Kamino README](https://github.com/t0mer/kamino#readme) for installation details.

### Command line

The `--repo` flag points any command at this repo. `validate` and `plan` only
read. `apply` installs software, and needs `sudo`.

```bash
# Validate this repo: schema version, item fields, dependency graph and
# per-arch source coverage:
kamino validate --repo https://github.com/t0mer/kamino-config

# See the resolved, ordered plan (and its warnings) for a profile:
kamino plan --repo https://github.com/t0mer/kamino-config --profile production

# Print the plan without installing anything:
sudo kamino apply --repo https://github.com/t0mer/kamino-config --profile dev --dry-run

# Install it, headless:
sudo kamino apply --repo https://github.com/t0mer/kamino-config --profile dev --yes
```

Useful extras:

- `--ref <branch|tag|sha>` picks a branch, tag or commit other than `main`.
- `--arch amd64|arm64` on `plan` shows the plan for another architecture.
- Profiles that contain items with secrets need their values on the command line:

  ```bash
  sudo kamino apply --repo https://github.com/t0mer/kamino-config --profile production --yes \
    --secret CF_TUNNEL_TOKEN=... --secret GRAFANA_ADMIN_PASSWORD=...
  ```

  `apply` refuses to start while a declared secret has no value.

> **Known issue:** as shipped, the `tools/motd` step fails on every run (see the
> [known issue](#known-issue-toolsmotd-fails-on-every-run)). It is in both the `production` and `dev`
> profiles, and `apply` stops at the first failed step unless you pass
> `--continue-on-error`, so the `apply` examples above stop at that step. Only
> `minimal` runs to completion today.

### Web UI

1. Run `sudo kamino serve`. It listens on `http://127.0.0.1:8844` and prints an
   API token the first time it starts.
2. Open the UI, paste the token, and on the **Connect** screen enter
   `https://github.com/t0mer/kamino-config` with branch `main`. **Test
   connection** checks that Kamino can reach the repo and finds a valid
   manifest. **Save** runs the same check.
3. On the **Setup** screen, pick a profile, review the plan and its warnings,
   and fill in any secrets the profile needs (`CF_TUNNEL_TOKEN`,
   `GRAFANA_ADMIN_PASSWORD` for `production`).
4. The **Run** screen streams live progress. **History** keeps past runs with
   their config SHA, result and logs.

## What's in this demo

Between them, the items use every runner Kamino implements (`apt`, `deb`,
`tarball`, `binary`, `pip`, `script` and `compose_stack`), plus dependency
ordering, per-arch sources, a version override, secrets, a repo-local script
and a compose stack.

The manifest (`manifest.yaml`) is named `kamino-demo`. It runs one
`apt-get update` at the start of every run (`apt_update_before_run: true`) and
gives each step a 15-minute timeout unless the item sets its own.

### Categories and items

Categories run in `order` (lowest first), and items keep their file order unless
a dependency says otherwise. `{version}` is replaced with the item's `version`
only in the fields listed under [Category items](#category-items) (`source`,
`check`, `check_contains`, `packages`, `pre_install`, `post_install`).

**`dev`: Development** (`order: 10`, [`categories/dev.yaml`](categories/dev.yaml))

| Item | Type | Version | Installs | Depends on | Skip check |
|---|---|---|---|---|---|
| `dev/go` (Go) | `tarball` | `1.24.5` | `https://go.dev/dl/go{version}.linux-{amd64,arm64}.tar.gz`, extracted into `/usr/local` (replacing `/usr/local/go`). Adds `/usr/local/go/bin` to `PATH` via `/etc/profile.d/kamino-go.sh`. Timeout `10m`. | — | `go version` contains `go{version}` |
| `dev/python` (Python) | `apt` | `3.12` | apt packages `python3.12`, `python3.12-venv`, `python3-pip` | — | `python3.12 --version` contains `Python 3.12` |
| `dev/pypi-base` (Base PyPI packages) | `pip` | — | `loguru`, `httpx`, `rich` with `python3.12 -m pip install --break-system-packages` | `dev/python` | `python3.12 -m pip show loguru` contains `Name: loguru` |
| `dev/uv` (uv, Python package manager) | `script` | — | runs `https://astral.sh/uv/install.sh` | — | `uv --version` contains `uv ` |

**`tools`: Tools** (`order: 20`, [`categories/tools.yaml`](categories/tools.yaml))

| Item | Type | Version | Installs | Depends on | Skip check |
|---|---|---|---|---|---|
| `tools/jq` (jq) | `apt` | — | apt package `jq` | — | `jq --version` contains `jq-` |
| `tools/ripgrep` (ripgrep) | `apt` | — | apt package `ripgrep` | — | `rg --version` contains `ripgrep` |
| `tools/htop` (htop) | `apt` | — | apt package `htop` | — | `htop --version` contains `htop` |
| `tools/yq` (yq) | `binary` | `4.44.3` | `https://github.com/mikefarah/yq/releases/download/v{version}/yq_linux_{amd64,arm64}` → `/usr/local/bin/yq` | — | `yq --version` contains `{version}` |
| `tools/motd` (Login banner) | `script` | — | runs [`scripts/setup-motd.sh`](scripts/setup-motd.sh) from this repo (see [below](#the-motd-script)) | — | `cat /etc/motd.kamino` contains `Provisioned by Kamino` |

**`containers`: Containers** (`order: 30`, [`categories/containers.yaml`](categories/containers.yaml))

| Item | Type | Version | Installs | Depends on | Skip check |
|---|---|---|---|---|---|
| `containers/docker` (Docker Engine) | `script` | — | runs `https://get.docker.com` | — | `docker --version` contains `Docker version` |
| `containers/docker-compose` (Docker Compose plugin) | `apt` | — | apt package `docker-compose-plugin` | `containers/docker` | `docker compose version` contains `Docker Compose version` |
| `containers/ctop` (ctop, container metrics) | `binary` | `0.7.7` | `https://github.com/bcicen/ctop/releases/download/v{version}/ctop-{version}-linux-{amd64,arm64}` → `/usr/local/bin/ctop` | `containers/docker` | `ctop -v` contains `{version}` |
| `containers/monitoring-stack` (Monitoring Stack, Prometheus + Grafana) | `compose_stack` | — | [`stacks/monitoring`](stacks/monitoring) (`docker-compose.yaml`, `prometheus.yml`), brought up with `docker compose up -d`. Secret: `GRAFANA_ADMIN_PASSWORD`. | `containers/docker`, `containers/docker-compose` | none (runs `up -d` every time, which reconciles the stack) |

**`network`: Network** (`order: 40`, [`categories/network.yaml`](categories/network.yaml))

| Item | Type | Version | Installs | Depends on | Skip check |
|---|---|---|---|---|---|
| `network/cloudflared` (Cloudflare Tunnel) | `deb` | `2024.8.2` | `https://github.com/cloudflare/cloudflared/releases/download/{version}/cloudflared-linux-{amd64,arm64}.deb`, then `post_install: cloudflared service install {secret:CF_TUNNEL_TOKEN}`. Secret: `CF_TUNNEL_TOKEN`. | — | `cloudflared --version` contains `{version}` |
| `network/tailscale` (Tailscale) | `script` | — | runs `https://tailscale.com/install.sh` | — | `tailscale version` contains `.` |

No item sets `arch`, so every item is offered on both `amd64` and `arm64`. None
sets `sha256` (see [Security notes](#security-notes)).

### Profiles

| Profile | Name | `include` | `exclude` | `overrides` | Resolved plan (in run order) |
|---|---|---|---|---|---|
| [`production`](profiles/production.yaml) | Production Server | `tools/*`, `containers/*`, `network/cloudflared` | `dev/*` | — | jq, ripgrep, htop, yq, motd, docker, docker-compose, ctop, monitoring-stack, cloudflared (10 steps). Needs `CF_TUNNEL_TOKEN` and `GRAFANA_ADMIN_PASSWORD`. |
| [`dev`](profiles/dev.yaml) | Developer Workstation | `dev/*`, `tools/*`, `containers/docker`, `containers/docker-compose` | — | `dev/go: { version: "1.23.4" }` | go **1.23.4**, python, pypi-base, uv, jq, ripgrep, htop, yq, motd, docker, docker-compose (11 steps). No secrets. |
| [`minimal`](profiles/minimal.yaml) | Minimal Toolbox | `tools/jq`, `tools/ripgrep`, `tools/htop` | — | — | jq, ripgrep, htop (3 steps). No secrets. |

`network/tailscale` is not in any profile. Add it to one (or write your own
profile) to install it. The `exclude: dev/*` in `production` changes nothing,
since `production` includes no `dev` items; it's there to show the syntax.

`production` and `dev` both include `tools/motd`, which currently fails (see the
[known issue](#known-issue-toolsmotd-fails-on-every-run)), so both profiles stop at that step
unless you run `apply --continue-on-error` or remove `tools/motd` from them.

The plan is the same on `amd64` and `arm64`. Run `kamino plan --profile <id>`
to see it, with a warning for each script, compose stack and unverified
download.

### The `motd` script

[`scripts/setup-motd.sh`](scripts/setup-motd.sh) is a repo-local script: the
`tools/motd` item sets `source: scripts/setup-motd.sh` instead of a URL. Kamino
fetches it from this repo, at the commit the run is pinned to, only when the
step runs, and runs it as root with `/bin/sh <file>`.

The script is meant to write this four-line banner to `/etc/motd.kamino`, print
`wrote /etc/motd.kamino`, and let the item's check (which reads that file) skip
the step on later runs:

```
────────────────────────────────────────
  Provisioned by Kamino
  https://github.com/t0mer/kamino
────────────────────────────────────────
```

#### Known issue: `tools/motd` fails on every run

Kamino runs scripts with `/bin/sh <file>`, so the script's `#!/usr/bin/env bash`
line is ignored. On Ubuntu `/bin/sh` is dash, which rejects the `pipefail`
option in `set -euo pipefail` (line 4), so the script exits before it writes
anything. The step fails, and because the file is never created, it fails again
on every run. `apply` stops at the first failed step unless you pass
`--continue-on-error`, so `production` and `dev` runs stop there.

Possible fixes in a fork: drop `pipefail` (use `set -eu`, which dash
accepts), or invoke bash explicitly, for example by making the script re-exec
itself under bash before the `set` line
(`[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"`).

Even once the script works, `/etc/motd.kamino` is only a marker file. Ubuntu's
`pam_motd` shows `/etc/motd` and the output of `/etc/update-motd.d/*`, not
`/etc/motd.kamino`, so the banner does not appear at login unless something
else wires it in.

### The monitoring stack

`containers/monitoring-stack` is a `compose_stack` item. At run time Kamino
fetches `docker-compose.yaml` and `prometheus.yml` from
[`stacks/monitoring/`](stacks/monitoring), writes them to a per-run temporary
directory, and runs `docker compose -p monitoring-stack -f … up -d`.

| Service | Image | Ports | Volumes | Notes |
|---|---|---|---|---|
| `prometheus` | `prom/prometheus:latest` | `9090:9090` | `./prometheus.yml:/etc/prometheus/prometheus.yml:ro` | `restart: unless-stopped` |
| `grafana` | `grafana/grafana:latest` | `3000:3000` | none | `restart: unless-stopped`, starts after `prometheus`. `GF_SECURITY_ADMIN_PASSWORD` is set from `${GRAFANA_ADMIN_PASSWORD:-admin}`. |

[`prometheus.yml`](stacks/monitoring/prometheus.yml) sets a `15s` global scrape
interval and one scrape job, `prometheus`, which scrapes `localhost:9090`
(Prometheus itself). No Grafana data source or dashboard is provisioned: add
Prometheus as a data source (`http://prometheus:9090` from inside the stack) in
Grafana yourself. The compose file declares no named data volumes. The
`prom/prometheus` image declares `VOLUME /prometheus`, so Prometheus data goes
to an anonymous Docker volume. Grafana has no volume at all, so its settings
live in the container and are lost when it is re-created.

`GRAFANA_ADMIN_PASSWORD` is declared in the item's `secrets`, so Kamino asks for
it and passes it to `docker compose` as an environment variable. It is never
written to disk. The web UI requires a non-blank value. On the CLI,
`--secret GRAFANA_ADMIN_PASSWORD=` (empty) is accepted, and Grafana then falls
back to `admin`.

**Known issue:** the `./prometheus.yml` bind mount's source is in Kamino's
per-run temporary directory, which Kamino removes when the run ends. After the
container is re-created or the Docker daemon restarts, the mount source is
gone and Prometheus can fail to start. Re-running the item brings the stack
back up with a fresh copy.

## Repository layout

| Path | Purpose |
|---|---|
| [`manifest.yaml`](manifest.yaml) | Entry point: schema version, name, defaults, and the lists of category and profile files. |
| [`categories/`](categories) | Installable items, grouped by category: `dev.yaml`, `tools.yaml`, `containers.yaml`, `network.yaml`. |
| [`profiles/`](profiles) | Named selections of items, with optional version overrides: `production.yaml`, `dev.yaml`, `minimal.yaml`. |
| [`scripts/`](scripts) | Shell scripts used by `script` items through a repo-relative `source` (`setup-motd.sh`). |
| [`stacks/monitoring/`](stacks/monitoring) | Docker Compose stack used by the `compose_stack` item (`docker-compose.yaml`, `prometheus.yml`). |
| [`.github/workflows/validate.yml`](.github/workflows/validate.yml) | CI that runs `kamino validate` on this repo. |
| [`LICENSE`](LICENSE) | Apache License 2.0. |

## Schema reference

The authoritative JSON Schema lives in the app repo under
[`schema/`](https://github.com/t0mer/kamino/tree/main/schema)
(`manifest.schema.json`, `category.schema.json`, `profile.schema.json`). Kamino
also rejects unknown fields when it parses these files, so a typo in a key is
an error rather than silently ignored.

Fields marked "required" below are required by the JSON Schema. `kamino
validate` doesn't check all of them (for example, a missing item `name` or
category `id` passes `validate`), so run the schema as well if you want them
enforced. See [Validation and CI](#validation-and-ci).

### `manifest.yaml`

```yaml
schema: 1                      # required, must be 1
name: kamino-demo              # required
defaults:
  apt_update_before_run: true  # run one `apt-get update` at the start of a run
  timeout: 15m                 # per-step default (^[0-9]+[smh]$); Kamino's own default is also 15m
categories:                    # required: paths to category files
  - categories/dev.yaml
profiles:                      # paths to profile files
  - profiles/production.yaml
```

### Category items

Each category file has `id`, `name`, optional `order`, and a list of `items`.
Category and item `id`s use lowercase letters, digits and `-`. Common item
fields:

| Field | Meaning |
|---|---|
| `id`, `name`, `type` | required; `type` is one of `apt`, `deb`, `tarball`, `binary`, `pip`, `script`, `compose_stack`, `snap`. `snap` is accepted by the schema, but Kamino has no runner for it, so a `snap` step fails. |
| `version` | version string; `{version}` is replaced in `source`, `check`, `check_contains`, `packages`, `pre_install` and `post_install` |
| `source` | download URL: a string (used for every arch) or a per-arch `{amd64, arm64}` map. Must be `https://`. A `script` item may instead give a repo-relative path (e.g. `scripts/foo.sh`), fetched from the config repo at run time |
| `sha256` | expected digest (string or per-arch map), checked before install for every download: `tarball`, `deb`, `binary`, and `script` items with an `https://` source. **If it's missing, the download is not verified.** `validate` and `plan` only warn about a missing digest for `tarball`, `deb` and `binary`. |
| `packages` | apt/pip package list (required for `apt` and `pip`) |
| `repo` | apt repository or PPA to add first (`add-apt-repository -y`) |
| `python` | interpreter version for `pip` items (`3.12` → `python3.12`; default `python3`) |
| `install_dir`, `path_export` | `tarball`: extraction dir (default `/usr/local`) and a directory to add to `PATH` via `/etc/profile.d/kamino-<id>.sh` |
| `path` | `compose_stack`: directory in this repo that holds the stack's files. `binary`: install destination (default `/usr/local/bin/<id>`) |
| `files` | `compose_stack`: files under `path` to fetch; must include a `docker-compose.y(a)ml` or `compose.y(a)ml` |
| `env_file` | accepted by the schema and the parser, but not used by any runner. Compose secrets come from `secrets`. |
| `depends_on` | list of `category/item` refs; drives ordering, and missing dependencies are pulled into the plan automatically |
| `check` + `check_contains` | idempotency probe: if `check` exits 0 and its output contains `check_contains` (or `check_contains` is empty), the step is **skipped** |
| `pre_install` / `post_install` | shell lines run before and after the install |
| `timeout` | per-step timeout (`^[0-9]+[smh]$`) |
| `arch` | restrict the item to `[amd64]` or `[arm64]` |
| `secrets` | names of secret values the UI/CLI must supply before a run |

### Profiles

```yaml
id: dev                                               # required
name: Developer Workstation                           # required
include: [ "dev/*", "tools/*", "containers/docker" ]  # exact refs or "category/*"
exclude: [ "dev/uv" ]                                 # exclude wins over include
overrides:
  dev/go: { version: "1.23.4" }                       # only `version` can be overridden
```

This is a syntax example; the real [`profiles/dev.yaml`](profiles/dev.yaml)
has no `exclude`. A pattern that matches no item is an error at plan time. If
an included item depends on something the profile excludes, the plan fails
instead of quietly adding it.

### Secrets

Values like `CF_TUNNEL_TOKEN` or `GRAFANA_ADMIN_PASSWORD` are **declared by name**
here, never by value. Kamino asks for them at run time (UI, or `--secret
KEY=VALUE` on the CLI), holds them in memory only, substitutes them for
`{secret:NAME}` placeholders (and passes them as environment variables to
compose stacks, for `${NAME}`), redacts them from logs, and never writes them
to disk.

## Customizing and forking

1. Fork this repo (it can be private: pass `--token`, or enter an access token
   on the Connect screen).
2. Edit the categories and profiles. Add an item by giving it an `id`, `name`
   and `type` plus the fields its type needs, then add its ref to a profile.
   Remember to list every new category or profile file in `manifest.yaml`.
3. Put repo-local scripts under `scripts/` and compose stacks under `stacks/`,
   and refer to them with a relative path (no leading `/`, no `..`).
4. Pin versions and add `sha256` digests for downloads (see
   [Security notes](#security-notes)).
5. Check the result before you use it on a server:

   ```bash
   kamino validate --repo https://github.com/<you>/<your-fork>
   kamino plan --repo https://github.com/<you>/<your-fork> --profile <id>
   ```

Kamino pins the ref to a commit SHA only for `github.com` and `gitlab.com`. On
other hosts (self-hosted GitLab, Gitea, Forgejo, …) you must pass a
`--raw-base` template, and the ref is used as given: pass a commit SHA as
`--ref` if you need the same guarantee.

## Validation and CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) runs on every
push, every pull request, and on manual dispatch. It checks out the repo, sets
up the latest stable Go, installs Kamino with
`go install github.com/t0mer/kamino/cmd/kamino@latest`, and runs
`kamino validate --config-dir .` against the checkout.

`kamino validate` fails on:

- a `schema` other than `1`, a file that can't be fetched, or invalid YAML or
  an unknown field in any file;
- duplicate category ids, or duplicate item ids within a category;
- an unknown item `type`;
- an `apt`, `pip` or `snap` item without `packages`;
- a `compose_stack` without `path`, without `files`, or without a compose file
  among its `files`;
- `check_contains` without `check`;
- a `tarball`, `deb` or `binary` item that has no `source` for a supported arch;
- a non-`https://` `source`, or a repo-relative `script` source that is
  absolute or contains `..`;
- a `depends_on` ref to an unknown item, or a dependency cycle.

It **warns** (and still passes) when a `tarball`, `deb` or `binary` item has no
`sha256`. Today it prints four warnings for this repo: `dev/go`, `tools/yq`,
`containers/ctop` and `network/cloudflared`.

What `validate` does **not** check:

- the JSON Schema's required fields and id format;
- profiles: include/exclude patterns that match nothing and excluded
  dependencies only fail at `plan`/`apply` time, and an override for an unknown
  item is silently ignored (it never fails);
- a `compose_stack`'s `path`. (Every category and profile file listed in
  `manifest.yaml` is fetched, so a wrong path fails validation, and with
  `--config-dir`, as CI uses, a path that escapes the directory is rejected.
  Repo-relative `script` sources get a path-safety check.);
- whether scripts and compose files exist (they're fetched only when their step
  runs).

To cover the gaps, run `kamino plan` for each profile, and validate the files
against Kamino's JSON Schema.

## Security notes

- **Everything in this repo runs as root.** `script` items run shell scripts
  from third-party URLs (`get.docker.com`, `astral.sh`, `tailscale.com`), and
  the compose stack runs through Docker. Only point Kamino at a config repo you
  control, and review changes to it the way you'd review code.
- **Add checksums.** No download in this demo has a `sha256`, so none of them is
  verified (`dev/go`, `tools/yq`, `containers/ctop`, `network/cloudflared`).
  For a hardened config, add the real per-arch digests. The `https://` installer
  scripts have no `sha256` either (Kamino would verify one if set), and they can
  change between runs.
- **Pin versions.** The Grafana and Prometheus images use `:latest`, and the CI
  workflow installs `kamino@latest` with the latest stable Go. Pin image tags
  (or digests) and tool versions so runs are reproducible.
- **Exposed ports.** The monitoring stack publishes `9090` and `3000` on all
  interfaces, and Prometheus has no authentication. Firewall them or bind them
  to `127.0.0.1`. Always supply a strong `GRAFANA_ADMIN_PASSWORD`; an empty
  value from the CLI falls back to Grafana's default.
- **Secrets in commands.** A `{secret:NAME}` in `pre_install`/`post_install`
  (as in `network/cloudflared`) is passed on a shell command line, where other
  local users can briefly see it in the process list. Kamino redacts it from
  its own logs only.
- **Never commit secret values** to this repo. Declare them by name in
  `secrets` and supply them at run time.

## License

[Apache-2.0](LICENSE).
