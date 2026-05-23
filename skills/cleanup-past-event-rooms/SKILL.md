---
name: cleanup-past-event-rooms
description: Cleans up Matrix event rooms whose date has passed by kicking members, pinging admins, and leaving the room. Defaults to dry-run; pass --execute to apply changes.
depends_on: [lib]
---

# cleanup-past-event-rooms

Cleans up Matrix event rooms whose date has passed:
1. Kicks all non-admin members with a thank-you message
2. Pings admin members asking them to leave the room manually via the web UI
3. Leaves the room

By default runs in **dry-run mode** — pass `--execute` to apply changes.

## Prerequisites

- `curl` and `python3` available in `PATH`
- A ChurchTools account with admin rights in the target rooms

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

# Preview what would happen (safe, no changes)
bash skills/cleanup-past-event-rooms/run.sh

# Apply
bash skills/cleanup-past-event-rooms/run.sh --execute
```

## How it identifies past event rooms

A room is a candidate when **all** of the following are true:

- Has a non-empty name
- Has **no** canonical alias (group chats have `#ctg_<guid>:…` aliases; event rooms don't)
- The name contains a German date pattern `DD.M.` or `DD.MM.` (e.g. `Gottesdienst am 17.5.`)
- That date lies strictly before today (year assumed to be current; if > 6 months in the future, previous year is used)

Rooms where the running user is not admin (power level < 100) are skipped and listed separately.

## Messages sent

**To the room before kicking regular members:**
> Der Gottesdienst ist rum, vielen Dank für Euren Dienst! 🙏

**Kick reason (visible in Matrix clients):**
> Der Gottesdienst ist rum, vielen Dank für Deinen Dienst!

**To each admin member (ping by display name):**
> Hallo \<Name\>! Danke für Deinen Dienst bei diesem Gottesdienst. Du bist Administrator dieses Raumes und musst ihn selbst verlassen — das geht nur über die Web-Oberfläche. Ich lasse dich jetzt allein. Liebe Grüße

## Shared library

This skill sources `skills/lib/ct-matrix-auth.sh` for ChurchTools→Matrix authentication.
See that file for details on the auth flow and exported variables.
