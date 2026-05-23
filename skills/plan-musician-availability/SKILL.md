---
name: plan-musician-availability
description: Reads Q3/Q4/… availability responses from the Musiker Matrix chat, cross-references them with ChurchTools group members and their instruments, and prints an availability table plus suggested band formations for each service.
depends_on: [lib]
---

# plan-musician-availability

Collects the availability replies that musicians post in the Musiker Matrix chat
after the quarterly planning request, maps each reply to the corresponding
ChurchTools group member (including their instrument from the member comment),
and generates:

The script collects all the data and outputs it in a structured format. The
agent running the skill then reads the output and performs the analysis using
its own language understanding — no extra API key required.

## Prerequisites

- `python3` available in `PATH`
- ChurchTools account with access to the Musiker group and the events calendar
- Active member of the Musiker Matrix chat room

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `CHURCHTOOLS_BASE_URL` | yes | Base URL, e.g. `https://your-church.church.tools` |
| `CHURCHTOOLS_LOGIN_TOKEN` | yes | API login token |
| `MATRIX_HOMESERVER` | no | Defaults to `https://chat.church.tools` |

## Usage

```bash
export CHURCHTOOLS_BASE_URL=https://your-church.church.tools
export CHURCHTOOLS_LOGIN_TOKEN=<your-token>

# Next quarter (default)
bash skills/plan-musician-availability/run.sh

# Specific quarter
bash skills/plan-musician-availability/run.sh Q3/26

# Explicit date range
bash skills/plan-musician-availability/run.sh 2026-07-01 2026-09-30
```

## How it works

1. **Auth**: sources `ct-matrix-auth.sh` to log into both ChurchTools and Matrix.
2. **Group members**: fetches all members of the ChurchTools group named `Musiker`
   and reads instruments from the member comment field (e.g. `Cajon`, `Gesang, Klavier`).
3. **Events**: fetches all Gottesdienste-like events in the quarter from ChurchTools.
4. **Messages**: fetches the last 500 messages in the Matrix room named `Musiker`,
   looking back 10 weeks before quarter start to capture both the request and all
   replies. Identifies the request by finding the coordinator's message that
   mentions the quarter label (e.g. `Q3/26`).
5. **Output**: prints the structured data — event list, member instruments, full
   message texts, non-responders — followed by instructions for the agent to
   produce the availability table and band formation suggestions.

## Limitations

- **Only responded members are shown** as available — non-responders are listed
  separately; do not assume they are free.
- **1x/Monat and spacing constraints are applied heuristically**: the agent
  respects stated frequency limits (e.g. "1x/Monat", "alle 6-7 Wochen") when
  suggesting formations, but the result should always be reviewed manually.
- **Message window is fixed at 500 messages / 10-week lookback**. If the planning
  cycle is longer or the chat is very busy, some responses may be missed.

## Notes

- Instrument data comes from the ChurchTools group member comment, not from
  service assignments. Keep member comments up to date.
- Members whose comment starts with `pausiert` are listed separately and excluded
  from formations.
- Run `request-musician-availability` first to generate and send the planning
  request, then run this skill a week or two later once replies have come in.
