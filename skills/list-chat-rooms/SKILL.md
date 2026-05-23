---
name: list-chat-rooms
description: Lists all Matrix rooms visible to the authenticated ChurchTools user, including rooms not exposed through the ChurchTools /api/chat endpoint
depends_on: [lib]
---

# list-chat-rooms

Lists all Matrix rooms visible to the authenticated ChurchTools user — including rooms that are not exposed through the ChurchTools `/api/chat` endpoint.

## Prerequisites

- `curl` and `python3` available in `PATH`
- A ChurchTools account with chat enabled (`canChat: true`)

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `CHURCHTOOLS_BASE_URL` | yes | Base URL of the ChurchTools instance, e.g. `https://your-church.church.tools` |
| `CHURCHTOOLS_LOGIN_TOKEN` | yes | API login token for the ChurchTools user |
| `MATRIX_HOMESERVER` | no | Matrix homeserver URL (default: `https://chat.church.tools`) |

## Usage

```bash
export CHURCHTOOLS_BASE_URL=https://your-church.church.tools
export CHURCHTOOLS_LOGIN_TOKEN=<your-token>

bash skills/list-chat-rooms/run.sh
```

## How it works

1. **ChurchTools auth** — calls `GET /api/whoami` with the login token to get the person's `id` and `guid`.
2. **Matrix password** — calls `GET /api/persons/{id}/logintoken` to get the per-person login token. ChurchTools uses this token as the Matrix password for accounts without a local ChurchTools password (SAML / 2FA users), which is the common case.
3. **Matrix user ID** — constructed as `@ct_<guid-lowercase>:<homeserver-host>`, e.g. `@ct_6bb4a0c2-...:chat.church.tools`.
4. **Matrix login** — calls `POST /_matrix/client/v3/login` with `m.login.password`.
5. **Room list** — calls `GET /_matrix/client/v3/joined_rooms` and resolves each room's display name via `GET /_matrix/client/v3/rooms/{roomId}/state/m.room.name`.

## Example output

```
Room ID                                        Name
----------------------------------------------------------------------
!FfTnwKHVkCjkckZDes:chat.church.tools          Musiker
!LIwRICqtTTSrhGbwYu:chat.church.tools          Baristas
!MXFNllrlUAWeuEwEjD:chat.church.tools          Gemeindebrief
...
```
