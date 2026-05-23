# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running skills

All skills require two environment variables:

```bash
export CHURCHTOOLS_BASE_URL=https://your-church.church.tools
export CHURCHTOOLS_LOGIN_TOKEN=<api-login-token>
```

Run a skill directly:

```bash
bash skills/<skill-name>/run.sh [args]
```

Notable flags:
- `cleanup-past-event-rooms` defaults to **dry-run**; pass `--execute` to apply changes
- `request-musician-availability` accepts `Q<n>/<yy>` (e.g. `Q4/26`) or an explicit `<from-date> <to-date>` range

## Architecture

Each skill lives under `skills/<skill-name>/` and consists of:
- `run.sh` — the executable entry point (bash + inline Python via heredoc)
- `SKILL.md` — metadata and documentation consumed by the `npx skills` toolchain

**Shared library:** `skills/lib/ct-matrix-auth.sh` must be *sourced* (not executed) by Matrix-facing skills. It exchanges a ChurchTools login token for a Matrix access token and exports `MATRIX_TOKEN`, `MATRIX_USER`, `MATRIX_HOMESERVER`, `HOMESERVER_HOST`, `PERSON_ID`, and `PERSON_GUID`. It also defines the `matrix_url_encode` helper.

**Auth flow:** ChurchTools `/api/whoami` → person GUID → `/api/persons/<id>/logintoken` → Matrix `/_matrix/client/v3/login` with `m.login.password`.

## Conventions

- Scripts use `set -euo pipefail`.
- JSON parsing uses inline Python 3 (`python3 -c "import json,sys; …"`), not `jq`.
- Matrix API calls use `curl -sf` with `Authorization: Bearer ${MATRIX_TOKEN}`.
- The `SKILL.md` frontmatter (`name`, `description`) is required for the `npx skills` registry to pick up a skill.
- All user-facing messages are in German (this is a FeG Limburg–specific setup).
