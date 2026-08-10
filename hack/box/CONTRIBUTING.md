# Contributing to ambox

This guide contains development and implementation details for contributors
working on the single-container ambox distribution.

## Development

Build a local seed cache image, then build and run the image locally:

    make seed-cache-local
    make run

`make build` provisions the `DemoTransferCSV` and `Images` sample transfers
from the sampledata revision pinned by this repository. It uses a filtered,
sparse checkout when the submodule is not already initialized. `make verify`
uses the same provisioner but requests only the `Images/pictures` directory.

The local `Makefile` defaults to `SEED_CACHE_IMAGE=ambox-build-cache-local`, so
`make seed-cache-local`, `make build`, and `make run` use the same seed cache
repo automatically. `make seed-cache-local` first tries to reuse a matching
remote seed cache tag and falls back to building the seed locally if none
exists. Re-run it after migration changes.

The bundled `hack/box/Makefile` mounts `test/ambox.yaml` and the SFTP test
keys under `test/` to simplify local development. Adjust those mounts if you
want different config or key paths.

Run `make verify` to build the image and process a bundled sample transfer into
an AIP and a DIP. The test starts ambox with fresh volumes mounted at the SFTP
upload directory and default AIP and DIP storage locations, uploads the sample
through SFTP, and checks that the stored AIP and DIP are readable from their
mounted locations. The pytest-bdd scenario also checks that jobs and tasks were
created and uses Playwright with Chromium to verify the transfer, virus scan,
and ingest results in Dashboard.
`make verify` installs the matching Chromium build automatically. Set
`AMBOX_SKIP_BUILD=1` to verify an existing `IMAGE:TAG`. On CI failures, browser
traces and screenshots, recent API responses, and container logs are uploaded
as artifacts. Pull requests run this end-to-end test in CI. Releases test the
amd64 candidate digest before publishing the version and `latest` manifests.

The release workflow defaults to a notes-only preview. It uses Copilot to
summarize the upstream Archivematica and ambox commit ranges, falling back to
deterministic commit lists when Copilot is unavailable. The generated Markdown
is shown in the job summary and uploaded as a workflow artifact. Previewing
does not build or publish images, push a tag, or create a GitHub Release:

    gh workflow run release.yml -f version=1.0.14

To compare generated notes with an existing release, preview its version. The
workflow automatically uses the matching existing tag as its target:

    gh workflow run release.yml -f version=1.0.13

The optional `target` input can preview a different historical tag or commit.

After reviewing a preview, run the workflow with publishing enabled to build
and test the images, publish the manifests, push the tag, and create the
GitHub Release:

    gh workflow run release.yml -f version=1.0.14 -f publish=true

## Runtime service dependencies

ambox uses [s6-overlay] to supervise Archivematica services in one container.
Each service is managed as an s6 service; its definition and dependencies are
in `s6-rc.d`. The graph below is derived from `s6-rc.d/*/dependencies`; arrows
point from prerequisite to dependent.

```mermaid
flowchart TB
  subgraph Core[Core services]
    mysql[mysql]
    gearmand[gearmand]
    clamd[clamd]
    sftpgo[sftpgo]
  end

  subgraph Bootstrap[Database bootstrap]
    mysql_init[mysql-init]
    db_seed[db-seed]
  end

  subgraph Checks[Startup checks]
    storage_access[storage-access]
  end

  subgraph SS[Storage Service]
    ss_migrate[ss-migrate]
    ss_gunicorn[ss-gunicorn]
  end

  subgraph Dash[Dashboard]
    dashboard_migrate[dashboard-migrate]
    dashboard_gunicorn[dashboard-gunicorn]
  end

  subgraph MCP[MCP]
    mcpserver[mcpserver]
    mcpclient[mcpclient]
  end

  subgraph Front[Front door]
    nginx[nginx]
    am_ready[am-ready]
  end

  subgraph Post[Post-boot]
    config[config]
  end

  mysql --> mysql_init --> db_seed
  storage_access --> sftpgo

  db_seed --> ss_migrate --> ss_gunicorn
  gearmand --> ss_gunicorn
  storage_access --> ss_gunicorn

  ss_gunicorn --> dashboard_migrate --> dashboard_gunicorn
  gearmand --> dashboard_migrate
  gearmand --> dashboard_gunicorn

  mysql_init --> mcpserver
  dashboard_migrate --> mcpserver
  gearmand --> mcpserver
  storage_access --> mcpserver
  mysql_init --> mcpclient
  ss_gunicorn --> mcpclient
  gearmand --> mcpclient
  clamd --> mcpclient
  storage_access --> mcpclient

  dashboard_gunicorn --> nginx
  ss_gunicorn --> nginx
  mcpserver --> am_ready
  mcpclient --> am_ready
  nginx --> am_ready
  am_ready --> config
```

| Service | Depends on |
| --- | --- |
| `mysql` | (none) |
| `gearmand` | (none) |
| `clamd` | (none) |
| `storage-access` | (none) |
| `sftpgo` | `storage-access` |
| `mysql-init` | `mysql` |
| `db-seed` | `mysql-init` |
| `ss-migrate` | `db-seed` |
| `ss-gunicorn` | `ss-migrate`, `gearmand`, `storage-access` |
| `dashboard-migrate` | `ss-gunicorn`, `gearmand` |
| `dashboard-gunicorn` | `dashboard-migrate`, `gearmand` |
| `mcpserver` | `mysql-init`, `gearmand`, `dashboard-migrate`, `storage-access` |
| `mcpclient` | `mysql-init`, `gearmand`, `ss-gunicorn`, `clamd`, `storage-access` |
| `nginx` | `dashboard-gunicorn`, `ss-gunicorn` |
| `am-ready` | `mcpserver`, `mcpclient`, `nginx` |
| `config` | `am-ready` |

## Dockerfile build stages

The `Dockerfile` uses a multi-stage build to construct the final runtime image.

| Stage | Depends on | Purpose |
| --- | --- | --- |
| `uv` | `ghcr.io/astral-sh/uv` | Provides uv binaries for Python management |
| `base` | `ubuntu:noble` | Foundation with locale setup and the `archivematica` user |
| `python-builder` | `base`, `uv` | Builds Python virtual environments for Archivematica and Storage Service |
| `frontend-builder` | `node:24` | Compiles Dashboard frontend assets |
| `seedcache-empty` | `scratch` | Empty placeholder stage for development and testing |
| `seedcache` | `${AM_SEED_CACHE_IMAGE}` | Provides SQL database dumps from an external artifact |
| `runtime-base` | `base`, `uv`, `python-builder` | Runtime system packages and Python virtual environments |
| `source` | `runtime-base`, `frontend-builder` | Adds source code and compiled frontend assets |
| `assets` | `runtime-base`, `frontend-builder` | Generates Django static assets and translations |
| `seed-builder` | `source` | Generates seed dumps for CI |
| `runtime` | `source`, `seedcache`, `assets` | Final distributable image |

```mermaid
flowchart TB
  subgraph External[External images]
    uv_ext["ghcr.io/astral-sh/uv"]
    ubuntu["ubuntu:noble"]
    node24["node:24"]
    scratch["scratch"]
    seed_arg["${AM_SEED_CACHE_IMAGE}<br/>(build argument)"]
  end

  subgraph Build[Build stages]
    uv["uv<br/><small>uv binaries</small>"]
    base["base<br/><small>Ubuntu foundation + archivematica user</small>"]
    python_builder["python-builder<br/><small>Python virtual environments</small>"]
    frontend_builder["frontend-builder<br/><small>Dashboard frontend</small>"]
    seedcache_empty["seedcache-empty<br/><small>Empty placeholder</small>"]
    seedcache["seedcache<br/><small>SQL dumps from artifact</small>"]
    runtime_base["runtime-base<br/><small>System packages + Python virtual environments</small>"]
    source["source<br/><small>Source code + frontend assets</small>"]
    assets["assets<br/><small>Django static assets + translations</small>"]
    seed_builder["seed-builder<br/><small>Generate seed dumps in CI</small>"]
    runtime["runtime<br/><small><b>FINAL IMAGE</b></small>"]
  end

  uv_ext --> uv
  ubuntu --> base
  node24 --> frontend_builder
  scratch --> seedcache_empty
  seed_arg --> seedcache

  base --> python_builder
  uv --> python_builder
  base --> runtime_base
  python_builder --> runtime_base
  uv --> runtime_base
  runtime_base --> source
  frontend_builder --> source
  runtime_base --> assets
  frontend_builder --> assets
  source --> seed_builder
  source --> runtime
  seedcache --> runtime
  assets --> runtime

  seed_builder -.->|produces in CI| seed_arg
```

The `runtime` stage is tagged and published. `seed-builder` produces the seed
cache artifact in CI, which is pushed to GHCR. Later builds consume it through
the `AM_SEED_CACHE_IMAGE` build argument rather than directly from that stage.

[s6-overlay]: https://github.com/just-containers/s6-overlay
