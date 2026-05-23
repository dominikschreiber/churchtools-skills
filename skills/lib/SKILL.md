---
name: lib
description: Shared shell library for ChurchTools→Matrix authentication. Required by cleanup-past-event-rooms, list-chat-rooms, and plan-musician-availability.
---

# lib

Shared shell library used by other churchtools-skills.

## ct-matrix-auth.sh

Authenticates a ChurchTools user against a Matrix homeserver using the
ChurchTools login token as the Matrix password. Source this file — do not
execute it directly.

### Required environment variables

| Variable | Description |
|---|---|
| `CHURCHTOOLS_BASE_URL` | Base URL of the ChurchTools instance, e.g. `https://your-church.church.tools` |
| `CHURCHTOOLS_LOGIN_TOKEN` | API login token for the ChurchTools user |

### Optional environment variables

| Variable | Default | Description |
|---|---|---|
| `MATRIX_HOMESERVER` | `https://chat.church.tools` | Matrix homeserver URL |

### Exported variables after sourcing

| Variable | Description |
|---|---|
| `MATRIX_TOKEN` | Matrix access token |
| `MATRIX_USER` | Matrix user ID, e.g. `@ct_<guid>:chat.church.tools` |
| `MATRIX_HOMESERVER` | Normalised homeserver URL |
| `HOMESERVER_HOST` | Host only, no protocol |
| `PERSON_ID` | ChurchTools person ID |
| `PERSON_GUID` | ChurchTools person GUID |

### Helper function

`matrix_url_encode <string>` — percent-encodes a string (e.g. a room ID containing `!` or `:`).

### Usage

```bash
# from within a skill's run.sh:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/ct-matrix-auth.sh"
# MATRIX_TOKEN, MATRIX_USER, … are now available
```
