---
name: request-musician-availability
description: Generates a quarterly musician availability request email by fetching the next quarter's Gottesdienst events from ChurchTools and identifying special services (Abendmahl, Livestream, Schulanfängergottesdienst, etc.) from event names and descriptions.
---

# request-musician-availability

Generates a draft email asking musicians for their scheduling preferences for
the upcoming quarter. Automatically determines which quarter is next, fetches
all Gottesdienst events for that period, highlights special services, and
prints a ready-to-copy-paste email in the established group style.

## Prerequisites

- `python3` available in `PATH`
- A ChurchTools account with access to the events calendar

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `CHURCHTOOLS_BASE_URL` | yes | Base URL of the ChurchTools instance, e.g. `https://your-church.church.tools` |
| `CHURCHTOOLS_LOGIN_TOKEN` | yes | API login token for the ChurchTools user |

## Usage

```bash
export CHURCHTOOLS_BASE_URL=https://your-church.church.tools
export CHURCHTOOLS_LOGIN_TOKEN=<your-token>

# Next quarter (default)
bash skills/request-musician-availability/run.sh

# Specific quarter
bash skills/request-musician-availability/run.sh Q4/26

# Custom date range (useful for testing)
bash skills/request-musician-availability/run.sh 2026-07-01 2026-09-30
```

Copy the output, paste it into the Musiker group notes in ChurchTools, and
adjust the deadline date if needed before sending.

## What it detects

Special services are identified by keywords in the event name or description:

| Keyword | Label in email |
|---|---|
| Abendmahl | Abendmahl |
| Livestream | Livestream |
| Schulanfänger / Schulstarter | Schulanfängergottesdienst |
| Taufe | Taufe |
| Kindersegnung | Kindersegnung |
| Erntedank | Erntedank |
| Karfreitag | Karfreitag |
| Ostern | Ostersonntag |
| Himmelfahrt | Himmelfahrt |
| Pfingsten | Pfingstsonntag |
| Weihnachten | Weihnachten |
| Heiligabend | Heiligabend |
| Jahresschluss | Jahresschlussandacht |
| Silvester | Silvester |

## Example output

```
[Musik-Planungs-Wünsche für Q3/26 bitte bis 2.6. an Jane; von Jane Doe; am 23.5.26]

_tl;dr: 13 Gottesdienste in Q3/26, davon besondere Gottesdienste: Abendmahl,
Schulanfängergottesdienst; Planungs-Wünsche bitte bis 2.6. an Jane_

Hallo ihr lieben Musiker:innen,

wir sind auf der Quartalshälfte und starten deswegen in die Planung von Q3/26,
d.h. Juli bis September. **Bitte schickt mir bis 2. Juni eure Planungs-Wünsche**
...

5.7. (Abendmahl)
12.7.
19.7.
...
```

## Notes

- The suggested deadline is the next Sunday ~2 weeks from today; adjust freely.
- Events that are not named "Gottesdienst" (e.g. Jugendkreis, GMV) are filtered out automatically.
- If the next quarter's events aren't in ChurchTools yet, the service list will be empty — add the events first and re-run.
