#!/usr/bin/env bash
# Generates a quarterly musician availability request email.
# Fetches Gottesdienst events from ChurchTools, identifies special services
# (Abendmahl, Livestream, Schulanfänger, etc.) from event names, and prints
# a draft email to stdout.
#
# Required environment variables:
#   CHURCHTOOLS_BASE_URL    e.g. https://your-instance.church.tools
#   CHURCHTOOLS_LOGIN_TOKEN  the API login token
#
# Optional argument:
#   Q<n>/<yy>              quarter to plan, e.g. Q3/26  (default: next quarter)
#   <YYYY-MM-DD> <YYYY-MM-DD>  explicit from/to date range

set -euo pipefail

: "${CHURCHTOOLS_BASE_URL:?CHURCHTOOLS_BASE_URL is required}"
: "${CHURCHTOOLS_LOGIN_TOKEN:?CHURCHTOOLS_LOGIN_TOKEN is required}"

python3 - "${CHURCHTOOLS_BASE_URL}" "${CHURCHTOOLS_LOGIN_TOKEN}" "$@" <<'PYEOF'
import sys, json, calendar, datetime, re
from urllib.request import urlopen

base_url, token = sys.argv[1], sys.argv[2]
args = sys.argv[3:]

whoami_url = f"{base_url}/api/whoami?login_token={token}"
with urlopen(whoami_url) as r:
    person = json.load(r)["data"]
coordinator_first = person.get("firstName", "")
coordinator_name = f"{person.get('firstName', '')} {person.get('lastName', '')}".strip()

today = datetime.date.today()

if len(args) == 0:
    # Default: next quarter
    current_quarter = (today.month - 1) // 3 + 1
    next_quarter = current_quarter % 4 + 1
    next_year = today.year if next_quarter > current_quarter else today.year + 1
    q_num, q_year = next_quarter, next_year
    q_start_month = (q_num - 1) * 3 + 1
elif len(args) == 1 and re.fullmatch(r'Q[1-4]/\d{2}', args[0]):
    # e.g. Q3/26
    q_num = int(args[0][1])
    q_year = 2000 + int(args[0][3:])
    q_start_month = (q_num - 1) * 3 + 1
elif len(args) == 2:
    # Explicit date range: YYYY-MM-DD YYYY-MM-DD
    from_date = datetime.date.fromisoformat(args[0])
    to_date   = datetime.date.fromisoformat(args[1])
    q_num, q_year, q_start_month = None, None, None
else:
    print(f"Usage: run.sh [Q<n>/<yy> | <from-date> <to-date>]", file=sys.stderr)
    sys.exit(1)

if q_start_month is not None:
    q_end_month = q_start_month + 2
    from_date = datetime.date(q_year, q_start_month, 1)
    to_date   = datetime.date(q_year, q_end_month, calendar.monthrange(q_year, q_end_month)[1])

url = f"{base_url}/api/events?login_token={token}&from={from_date}&to={to_date}"
with urlopen(url) as r:
    events = json.load(r)["data"]

SPECIAL_MARKERS = [
    ("Abendmahl",        "Abendmahl"),
    ("Livestream",       "Livestream"),
    ("Schulanfänger",    "Schulanfängergottesdienst"),
    ("Schulstarter",     "Schulanfängergottesdienst"),
    ("Taufe",            "Taufe"),
    ("Kindersegnung",    "Kindersegnung"),
    ("Erntedank",        "Erntedank"),
    ("Karfreitag",       "Karfreitag"),
    ("Ostern",           "Ostersonntag"),
    ("Himmelfahrt",      "Himmelfahrt"),
    ("Pfingsten",        "Pfingstsonntag"),
    ("Weihnachten",      "Weihnachten"),
    ("Heiligabend",      "Heiligabend"),
    ("Jahresschluss",    "Jahresschlussandacht"),
    ("Silvester",        "Silvester"),
]

def specials(event):
    name = (event.get("name") or "")
    seen = []
    for kw, label in SPECIAL_MARKERS:
        if kw.lower() in name.lower() and label not in seen:
            seen.append(label)
    return seen

def is_gottesdienst(event):
    name = event.get("name") or ""
    return "Gottesdienst" in name or any(
        kw.lower() in name.lower()
        for kw, _ in SPECIAL_MARKERS
        if kw in ("Schulanfänger", "Schulstarter")
    )

services = []
for ev in events:
    if not is_gottesdienst(ev):
        continue
    d = datetime.date.fromisoformat(ev["startDate"][:10])
    services.append((d, specials(ev)))

services.sort()

MONTHS = ["Januar","Februar","März","April","Mai","Juni",
          "Juli","August","September","Oktober","November","Dezember"]

if q_num is not None:
    q_label  = f"Q{q_num}/{str(q_year)[2:]}"
    q_months = f"{MONTHS[q_start_month-1]} bis {MONTHS[q_start_month+1]}"
else:
    q_label  = f"{from_date} – {to_date}"
    q_months = q_label

# Deadline: next Sunday in ~2 weeks
days_to_sunday = (6 - today.weekday()) % 7 or 7
deadline = today + datetime.timedelta(days=7 + days_to_sunday)

def fd(d):
    return f"{d.day}.{d.month}."

print(f"[Musik-Planungs-Wünsche für {q_label} bitte bis {fd(deadline)} an {coordinator_first}; von {coordinator_name}; am {fd(today)}{str(today.year)[2:]}]")
print()

n = len(services)
all_specials = []
for _, sp in services:
    for s in sp:
        if s not in all_specials:
            all_specials.append(s)
specials_note = f", davon besondere Gottesdienste: {', '.join(all_specials)}" if all_specials else ""
print(f"_tl;dr: {n} Gottesdienste in {q_label}{specials_note}; Planungs-Wünsche bitte bis {fd(deadline)} an {coordinator_first}_")
print()
print("Hallo ihr lieben Musiker:innen,")
print()
print(f"wir sind auf der Quartalshälfte und starten deswegen in die Planung von {q_label}, d.h. {q_months}.")
print(f"**Bitte schickt mir bis {deadline.day}. {MONTHS[deadline.month-1]} eure Planungs-Wünsche**")
print("(am besten als Chat-Nachricht in ChurchTools, notfalls auch per Mail, aber irgendwie schriftlich):")
print()
print("- Wie oft wollt ihr im Quartal eingeteilt werden?")
print("- An welchen Terminen könnt ihr nicht?")
print("- Mit wem möchtet ihr gern eingeteilt werden?")
print("- Möchtet ihr z.B. nicht im Livestream eingeteilt werden?")
print("- Habt ihr weiteren Input?")
print()
print(f"{q_label} hat folgende {n} Gottesdienste:")
print()
for d, sp in services:
    marker = f" ({', '.join(sp)})" if sp else ""
    print(f"{fd(d)}{marker}")
print()
print(f"Den fertigen Plan bekommt ihr dann gegen Ende {MONTHS[deadline.month-1]}.")
print()
print("Liebe Grüße")
print(coordinator_first)
PYEOF
