# churchtools-skills

Shell scripts for automating ChurchTools administration tasks, with a focus on Matrix chat room management and musician coordination.

> [!NOTE]
> These skills are highly tailored to the specific setup and workflows at [FeG Limburg](https://feg-limburg.de). They may not work out of the box for other ChurchTools instances without adaptation.

## Installation

```bash
npx skills add dominikschreiber/churchtools-skills
```

## Prerequisites

- `curl` and `python3` available in `PATH`
- A ChurchTools account with an API login token

## Environment variables

All skills require these two variables:

| Variable | Description |
|---|---|
| `CHURCHTOOLS_BASE_URL` | Base URL of your ChurchTools instance, e.g. `https://your-church.church.tools` |
| `CHURCHTOOLS_LOGIN_TOKEN` | API login token for the ChurchTools user |

Some skills also accept `MATRIX_HOMESERVER` (default: `https://chat.church.tools`).

## Skills

### `cleanup-past-event-rooms`

Cleans up Matrix event rooms whose date has passed: kicks regular members with a thank-you message, pings admin members to leave manually, and leaves the room.

Defaults to **dry-run** — pass `--execute` to apply changes.

```bash
bash skills/cleanup-past-event-rooms/run.sh          # preview
bash skills/cleanup-past-event-rooms/run.sh --execute # apply
```

### `list-chat-rooms`

Lists all Matrix rooms visible to the authenticated ChurchTools user, including rooms not exposed through the ChurchTools `/api/chat` endpoint.

```bash
bash skills/list-chat-rooms/run.sh
```

### `request-musician-availability`

Generates a ready-to-send email asking musicians for their scheduling preferences for the upcoming quarter. Fetches Gottesdienst events from ChurchTools and highlights special services (Abendmahl, Livestream, Schulanfängergottesdienst, etc.).

```bash
bash skills/request-musician-availability/run.sh         # next quarter
bash skills/request-musician-availability/run.sh Q4/26   # specific quarter
```

### `plan-musician-availability`

Collects availability replies from the Musiker Matrix chat, cross-references them with the active musician sub-groups ("Aktive Pianisten", "Aktive Sänger", etc.) for instrument data, and outputs structured data for an AI agent to produce an availability table and concrete band formation suggestions — respecting each musician's stated frequency constraints (1x/month, every 6–7 weeks, etc.).

Run after replies have come in from `request-musician-availability`.

```bash
bash skills/plan-musician-availability/run.sh         # next quarter
bash skills/plan-musician-availability/run.sh Q3/26   # specific quarter
```

## Shared library

`skills/lib/ct-matrix-auth.sh` handles ChurchTools→Matrix authentication and is sourced by skills that interact with Matrix. It exchanges the ChurchTools login token for a Matrix access token and exports `MATRIX_TOKEN`, `MATRIX_USER`, and related variables.
