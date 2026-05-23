#!/usr/bin/env bash
# Cleans up past event-specific Matrix rooms:
#   - kicks non-admin members with a thank-you message
#   - pings admin members asking them to leave manually
#   - leaves the room
#
# A room is a past event room when it has a name, no canonical alias, and a
# German date (DD.M. or DD.MM.) in the name that lies before today.
#
# Required environment variables:
#   CHURCHTOOLS_BASE_URL    e.g. https://your-instance.church.tools
#   CHURCHTOOLS_LOGIN_TOKEN  the API login token for the ChurchTools user
#
# Optional:
#   MATRIX_HOMESERVER       defaults to https://chat.church.tools
#
# Flags:
#   --execute   actually kick/message/leave (default: dry-run)

set -euo pipefail

EXECUTE=false
for arg in "$@"; do
  [[ "$arg" == "--execute" ]] && EXECUTE=true
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ct-matrix-auth.sh
source "${SCRIPT_DIR}/../lib/ct-matrix-auth.sh"

# ── helpers ────────────────────────────────────────────────────────────────────

warn() { echo "  [WARN] $*" >&2; }

matrix_get_state() {
  # matrix_get_state <room_id> <event_type> [field]
  local room_id="$1" event_type="$2" field="${3:-}"
  local encoded; encoded=$(matrix_url_encode "$room_id")
  local response
  response=$(curl -sf \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${encoded}/state/${event_type}" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" 2>/dev/null) || { echo ""; return 0; }
  if [[ -n "$field" ]]; then
    echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('${field}',''))" 2>/dev/null || echo ""
  else
    echo "$response"
  fi
}

matrix_send_message() {
  # matrix_send_message <room_id> <text>
  local room_id="$1" text="$2"
  local encoded; encoded=$(matrix_url_encode "$room_id")
  local txn_id="cleanup_$$_${RANDOM}"
  curl -sf -X PUT \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${encoded}/send/m.room.message/${txn_id}" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"msgtype\":\"m.text\",\"body\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text")}" \
    > /dev/null
}

matrix_kick() {
  # matrix_kick <room_id> <user_id> <reason>
  local room_id="$1" user_id="$2" reason="$3"
  local encoded; encoded=$(matrix_url_encode "$room_id")
  curl -sf -X POST \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${encoded}/kick" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$user_id"),\"reason\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$reason")}" \
    > /dev/null
}

matrix_leave() {
  # matrix_leave <room_id>
  local room_id="$1"
  local encoded; encoded=$(matrix_url_encode "$room_id")
  curl -sf -X POST \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/${encoded}/leave" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}' \
    > /dev/null
}

is_past_event_room() {
  # is_past_event_room <name> <canonical_alias>
  # returns 0 (true) or 1 (false)
  local name="$1" alias="$2"
  [[ -z "$name" ]] && return 1
  [[ -n "$alias" ]] && return 1  # group chats have aliases; event rooms don't
  python3 - "$name" <<'PYEOF'
import sys, re
from datetime import date, timedelta

name = sys.argv[1]
m = re.search(r'(\d{1,2})\.(\d{1,2})\.', name)
if not m:
    sys.exit(1)

day, month = int(m.group(1)), int(m.group(2))
today = date.today()
try:
    candidate = date(today.year, month, day)
except ValueError:
    sys.exit(1)

# If the candidate is more than 6 months in the future, it's probably last year
if (candidate - today).days > 180:
    try:
        candidate = date(today.year - 1, month, day)
    except ValueError:
        sys.exit(1)

sys.exit(0 if candidate < today else 1)
PYEOF
}

# ── main ───────────────────────────────────────────────────────────────────────

if $EXECUTE; then
  echo "Mode: EXECUTE"
else
  echo "Mode: DRY-RUN (pass --execute to apply changes)"
fi
echo ""

ROOMS=$(curl -sf "${MATRIX_HOMESERVER}/_matrix/client/v3/joined_rooms" \
  -H "Authorization: Bearer ${MATRIX_TOKEN}" \
  | python3 -c "import json,sys; [print(r) for r in sorted(json.load(sys.stdin)['joined_rooms'])]")

count_cleanup=0
count_skip=0

while IFS= read -r room_id; do
  name=$(matrix_get_state "$room_id" "m.room.name" "name")
  alias=$(matrix_get_state "$room_id" "m.room.canonical_alias" "alias")

  if ! is_past_event_room "$name" "$alias"; then
    continue
  fi

  # Check own power level
  power_levels_json=$(matrix_get_state "$room_id" "m.room.power_levels")
  own_power=$(python3 - "$power_levels_json" "$MATRIX_USER" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
user = sys.argv[2]
level = data.get("users", {}).get(user, data.get("users_default", 0))
print(level)
PYEOF
  )

  if [[ "$own_power" -lt 100 ]]; then
    echo "[SKIP] ${name} (${room_id}) — not admin (own power level: ${own_power})"
    (( count_skip++ )) || true
    continue
  fi

  # Get joined members (excluding self)
  members_json=$(curl -sf \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/$(matrix_url_encode "$room_id")/joined_members" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}")

  # Classify members
  regular_members=()
  regular_display_names=()
  admin_members=()
  admin_display_names=()

  while IFS=$'\t' read -r uid display_name power; do
    [[ "$uid" == "$MATRIX_USER" ]] && continue
    if [[ "$power" -ge 100 ]]; then
      admin_members+=("$uid")
      admin_display_names+=("$display_name")
    else
      regular_members+=("$uid")
      regular_display_names+=("$display_name")
    fi
  done < <(python3 - "$power_levels_json" "$members_json" <<'PYEOF'
import json, sys

pl = json.loads(sys.argv[1])
members = json.loads(sys.argv[2])

user_powers = pl.get("users", {})
default_power = pl.get("users_default", 0)

for uid, info in members.get("joined", {}).items():
    display_name = info.get("display_name") or uid
    power = user_powers.get(uid, default_power)
    print(f"{uid}\t{display_name}\t{power}")
PYEOF
  )

  echo "[CANDIDATE] ${name} (${room_id})"

  if [[ ${#regular_members[@]} -gt 0 ]]; then
    echo "  regular members to kick:"
    for i in "${!regular_members[@]}"; do
      echo "    - ${regular_display_names[$i]} (${regular_members[$i]})"
    done
    echo "  broadcast message:"
    echo "    \"Der Gottesdienst ist rum, vielen Dank für Euren Dienst! 🙏\""
    echo "  kick reason:"
    echo "    \"Der Gottesdienst ist rum, vielen Dank für Deinen Dienst!\""
  else
    echo "  regular members to kick: (none)"
  fi

  if [[ ${#admin_members[@]} -gt 0 ]]; then
    echo "  admin members to ping:"
    for i in "${!admin_members[@]}"; do
      echo "    - ${admin_display_names[$i]} (${admin_members[$i]})"
      echo "      message: \"Hallo ${admin_display_names[$i]}! Danke für Deinen Dienst bei diesem Gottesdienst. Du bist Administrator dieses Raumes und musst ihn selbst verlassen — das geht nur über die Web-Oberfläche. Ich lasse dich jetzt allein. Liebe Grüße\""
    done
  else
    echo "  admin members to ping: (none)"
  fi

  if $EXECUTE; then
    # Thank-you message before kicking
    if [[ ${#regular_members[@]} -gt 0 ]]; then
      matrix_send_message "$room_id" \
        "Der Gottesdienst ist rum, vielen Dank für Euren Dienst! 🙏" \
        || warn "could not send thank-you message"
      for i in "${!regular_members[@]}"; do
        matrix_kick "$room_id" "${regular_members[$i]}" \
          "Der Gottesdienst ist rum, vielen Dank für Deinen Dienst!" \
          && echo "  kicked: ${regular_display_names[$i]} (${regular_members[$i]})" \
          || warn "could not kick ${regular_members[$i]}"
      done
    fi

    # Ping admins
    if [[ ${#admin_members[@]} -gt 0 ]]; then
      for i in "${!admin_members[@]}"; do
        matrix_send_message "$room_id" \
          "Hallo ${admin_display_names[$i]}! Danke für Deinen Dienst bei diesem Gottesdienst. Du bist Administrator dieses Raumes und musst ihn selbst verlassen — das geht nur über die Web-Oberfläche. Ich lasse dich jetzt allein. Liebe Grüße" \
          && echo "  pinged admin: ${admin_display_names[$i]} (${admin_members[$i]})" \
          || warn "could not ping admin ${admin_members[$i]}"
      done
    fi

    matrix_leave "$room_id" \
      && echo "  → left room" \
      || warn "could not leave room"
  else
    echo "  → would leave room"
  fi

  echo ""
  (( count_cleanup++ )) || true

done <<< "$ROOMS"

echo "--- Summary ---"
if $EXECUTE; then
  echo "${count_cleanup} room(s) cleaned up"
else
  echo "${count_cleanup} room(s) would be cleaned up"
fi
echo "${count_skip} room(s) skipped (not admin)"
