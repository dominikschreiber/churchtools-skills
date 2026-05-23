#!/usr/bin/env bash
# Collects Q3/Q4/… availability responses from the Musiker Matrix chat,
# cross-references them with ChurchTools group members (instruments from member
# comments), and prints an availability table + suggested band formations.
#
# Required environment variables:
#   CHURCHTOOLS_BASE_URL    e.g. https://your-instance.church.tools
#   CHURCHTOOLS_LOGIN_TOKEN  the API login token
#
# Optional:
#   MATRIX_HOMESERVER       defaults to https://chat.church.tools
#
# Usage:
#   run.sh              → next quarter
#   run.sh Q3/26        → specific quarter
#   run.sh 2026-07-01 2026-09-30  → explicit date range

set -euo pipefail

: "${CHURCHTOOLS_BASE_URL:?CHURCHTOOLS_BASE_URL is required}"
: "${CHURCHTOOLS_LOGIN_TOKEN:?CHURCHTOOLS_LOGIN_TOKEN is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ct-matrix-auth.sh
source "${SCRIPT_DIR}/../lib/ct-matrix-auth.sh"

python3 - \
  "${CHURCHTOOLS_BASE_URL}" \
  "${CHURCHTOOLS_LOGIN_TOKEN}" \
  "${MATRIX_HOMESERVER}" \
  "${MATRIX_TOKEN}" \
  "$@" <<'PYEOF'
import sys, json, re, calendar, datetime
from urllib.request import urlopen, Request
from urllib.parse import quote as url_quote
from urllib.error import HTTPError
import http.cookiejar, urllib.request

base_url   = sys.argv[1]
token      = sys.argv[2]
homeserver = sys.argv[3]
mx_token   = sys.argv[4]
args       = sys.argv[5:]

today = datetime.date.today()

# ── 1. Parse quarter / date-range argument ─────────────────────────────────
if len(args) == 0:
    current_q  = (today.month - 1) // 3 + 1
    q_num      = current_q % 4 + 1
    q_year     = today.year if q_num > current_q else today.year + 1
elif len(args) == 1 and re.fullmatch(r'Q[1-4]/\d{2}', args[0]):
    q_num  = int(args[0][1])
    q_year = 2000 + int(args[0][3:])
elif len(args) == 2:
    from_date = datetime.date.fromisoformat(args[0])
    to_date   = datetime.date.fromisoformat(args[1])
    q_num, q_year = None, None
else:
    print("Usage: run.sh [Q<n>/<yy> | <from-date> <to-date>]", file=sys.stderr)
    sys.exit(1)

if q_num is not None:
    q_sm      = (q_num - 1) * 3 + 1
    from_date = datetime.date(q_year, q_sm, 1)
    to_date   = datetime.date(q_year, q_sm + 2,
                              calendar.monthrange(q_year, q_sm + 2)[1])
    q_label   = f"Q{q_num}/{str(q_year)[2:]}"
else:
    q_label   = f"{from_date} – {to_date}"

# ── 2. ChurchTools session (cookie auth) ───────────────────────────────────
jar    = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
opener.open(f"{base_url}/api/whoami?login_token={token}")

def ct(path):
    with opener.open(f"{base_url}{path}") as r:
        return json.load(r)

# ── 3. Matrix helper ───────────────────────────────────────────────────────
def mx(path):
    req = Request(f"{homeserver}{path}",
                  headers={"Authorization": f"Bearer {mx_token}"})
    with urlopen(req) as r:
        return json.load(r)

def mx_room_name(room_id):
    try:
        return mx(f"/_matrix/client/v3/rooms/{url_quote(room_id, safe='')}"
                  f"/state/m.room.name").get("name", "")
    except (HTTPError, Exception):
        return ""

# ── 4. Fetch active musician sub-groups (instrument source) ───────────────
print("Loading active musician sub-groups …", file=sys.stderr)
all_groups = ct("/api/groups?query=Aktive&limit=100").get("data", [])
aktive_groups = [g for g in all_groups if g.get("name", "").startswith("Aktive ")]
if not aktive_groups:
    print("ERROR: No 'Aktive …' sub-groups found in ChurchTools.", file=sys.stderr)
    sys.exit(1)

# guid → {name, groups: [group names]}
guid_info = {}
for grp in aktive_groups:
    for m in ct(f"/api/groups/{grp['id']}/members?limit=100").get("data", []):
        da   = m.get("person", {}).get("domainAttributes", {})
        guid = da.get("guid", "").lower()
        if not guid: continue
        name = f"{da.get('firstName','')} {da.get('lastName','')}".strip()
        if guid not in guid_info:
            guid_info[guid] = {"name": name, "groups": []}
        guid_info[guid]["groups"].append(grp["name"])

# ── 5. Fetch Gottesdienste for the quarter ─────────────────────────────────
print(f"Loading services for {q_label} …", file=sys.stderr)
GOTTESDIENST_KW = [
    "Gottesdienst","Abendmahl","Taufe","Erntedank","Karfreitag","Ostern",
    "Himmelfahrt","Pfingsten","Weihnachten","Heiligabend","Schulanfänger",
    "Schulstarter","Jahresschluss","Silvester",
]
services = []
for e in ct(f"/api/events?from={from_date}&to={to_date}&limit=100").get("data", []):
    name = e.get("name", "")
    if any(k.lower() in name.lower() for k in GOTTESDIENST_KW):
        d = datetime.date.fromisoformat(e["startDate"][:10])
        services.append((d, name))
services.sort()

def service_key(d):
    return f"{d.day:02d}.{d.month:02d}."

# ── 6. Find the Musiker Matrix room ───────────────────────────────────────
print("Looking up Musiker Matrix room …", file=sys.stderr)
joined_rooms = mx("/_matrix/client/v3/joined_rooms")["joined_rooms"]
musiker_room = next(
    (r for r in joined_rooms if mx_room_name(r).lower() == "musiker"), None
)
if not musiker_room:
    print("ERROR: Matrix room 'Musiker' not found.", file=sys.stderr)
    sys.exit(1)

# ── 7. Fetch messages (10 weeks before quarter start to catch the request) ─
lookback = from_date - datetime.timedelta(weeks=10)
lookback_ts = int(datetime.datetime(lookback.year, lookback.month, lookback.day,
                                    tzinfo=datetime.timezone.utc).timestamp() * 1000)
print(f"Fetching Matrix messages since {lookback} …", file=sys.stderr)

enc_room = url_quote(musiker_room, safe="")
chunk    = mx(f"/_matrix/client/v3/rooms/{enc_room}/messages?limit=500&dir=b")
raw_events = chunk.get("chunk", [])

GUID_RE = re.compile(r'@ct_([^:]+):')

# Collect text messages per sender guid
all_msgs = []   # (ts, guid, body)
for e in raw_events:
    if e.get("type") != "m.room.message": continue
    c = e.get("content", {})
    if c.get("msgtype") != "m.text": continue
    ts   = e["origin_server_ts"]
    if ts < lookback_ts: continue
    mo   = GUID_RE.match(e["sender"])
    if not mo: continue
    guid = mo.group(1).lower()
    body = c.get("body", "")
    if body.startswith("> "): continue   # skip quoted replies
    all_msgs.append((ts, guid, body))

all_msgs.sort()

# ── 8. Find request timestamp (first coordinator message mentioning the quarter)
# Coordinator = the account whose GUID is in MATRIX_USER env
coord_guid_match = GUID_RE.match(
    __import__('os').environ.get("MATRIX_USER","")
)
coord_guid = coord_guid_match.group(1).lower() if coord_guid_match else None

request_ts = lookback_ts
for ts, guid, body in all_msgs:
    if guid == coord_guid and (q_label in body or f"Q{q_num}" in body if q_num else False):
        request_ts = ts
        break

# Keep only messages sent AFTER the request (coordinator's request itself excluded)
responses_raw = [(ts, guid, body) for ts, guid, body in all_msgs if ts > request_ts]

# Group by guid
guid_to_msgs = {}
for ts, guid, body in responses_raw:
    guid_to_msgs.setdefault(guid, []).append(body)

# ── 9. Render output ──────────────────────────────────────────────────────
SPECIAL_KW = ["Abendmahl","Taufe","Schulanfänger","Livestream","Erntedank"]
WEEKDAYS_DE = ["Mo","Di","Mi","Do","Fr","Sa","So"]

def spec_label(evname):
    found = [k for k in SPECIAL_KW if k.lower() in evname.lower()]
    return f" ({', '.join(found)})" if found else ""

def role_icons(groups):
    icons = []
    pairs = [
        (["Pianist"],              "🎹"),
        (["Sänger", "Sängerinnen"],"🎤"),
        (["Gitarrist", "Gitarre"], "🎸"),
        (["Bassist", "Bass"],      "🎸"),
        (["Schlagzeug", "Cajon"],  "🥁"),
        (["Flöt", "Saxo", "Bläser"],"🎵"),
    ]
    seen = set()
    for keywords, ico in pairs:
        if ico not in seen and any(
            any(k.lower() in g.lower() for k in keywords) for g in groups
        ):
            icons.append(ico)
            seen.add(ico)
    return "".join(icons) or "🎵"

sorted_members = sorted(guid_info.items(), key=lambda x: x[1]["name"])
responded   = [(g, i) for g, i in sorted_members if guid_to_msgs.get(g)]
no_response = [(g, i) for g, i in sorted_members if not guid_to_msgs.get(g)]

print(f"=== MUSICIAN PLANNING {q_label} ===")
print()
print(f"SERVICES ({len(services)}):")
for d, evname in services:
    wd = WEEKDAYS_DE[d.weekday()]
    print(f"  {wd} {d.day:02d}.{d.month:02d}.{spec_label(evname)}")

print()
print("INSTRUMENTS (from sub-group membership):")
for guid, info in sorted_members:
    groups_str = ", ".join(info["groups"])
    print(f"  {info['name']} | {groups_str}")

print()
print("AVAILABILITY REPLIES:")
print()
for guid, info in responded:
    msgs = guid_to_msgs[guid]
    groups_str = ", ".join(info["groups"])
    print(f"{info['name']} [{groups_str}]:")
    for msg in msgs:
        for line in msg.strip().splitlines():
            print(f"  {line}")
    print()

if no_response:
    print(f"NO REPLY YET ({len(no_response)}):")
    for _, info in no_response:
        groups_str = ", ".join(info["groups"])
        print(f"  {info['name']} | {groups_str}")
    print()

print("=" * 72)
print("""AGENT TASK:

Analyse the replies above and produce:

1. AVAILABILITY TABLE: For each person who replied and each service date:
   ✓ (available), ✗ (not available), ? (unclear / no statement).
   The replies are in German — interpret them accordingly, e.g.:
   - "im Juli nicht" → all July dates ✗
   - "immer" / "kann immer" → all dates ✓
   - "alles möglich außer 06.09." → all Sept. dates ✓ except 06.09. ✗
   - "nur der 05.07." → 05.07. ✓, all other July dates ✗
   - Messages with no date reference → all ?
   - Do NOT reflect 1x/month preferences in the table (handled manually)

2. FREQUENCY CONSTRAINTS: Before building formations, list each replying
   person's stated frequency limit, e.g.:
     Hanna Schreiber: 1x/month
     Ulrich Hoffmann: every 6-7 weeks
     Wim Zaan: no limit stated
   Use this list as a reference for step 3.

3. SUGGESTED BAND FORMATIONS: Produce one concrete band assignment per
   service date. Apply all constraints:
   - A person with "1x/Monat" may appear in at most ONE date per calendar
     month across the entire formation table — not once per available date.
   - A person with "alle 6-7 Wochen" must have at least 6 weeks between
     any two of their assigned dates.
   - Honour explicit unavailability (✗ dates); never assign someone on a ✗.
   - Prefer ✓ over ? when filling slots, but use ? where necessary.
   - People who did not reply are a last resort; mark them as "(?)" .
   Required per service: 1 pianist + 1 singer.
   Optional: cajon/drums, guitar, bass, additional singers.
   After the table, list any dates where a complete band is not possible and
   explain what is missing.""")

PYEOF
