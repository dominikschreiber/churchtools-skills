#!/usr/bin/env bash
# Lists all Matrix rooms visible to the authenticated ChurchTools user.
#
# Required environment variables:
#   CHURCHTOOLS_BASE_URL    e.g. https://your-instance.church.tools
#   CHURCHTOOLS_LOGIN_TOKEN  the API login token for the ChurchTools user
#
# Optional:
#   MATRIX_HOMESERVER       defaults to https://chat.church.tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ct-matrix-auth.sh
source "${SCRIPT_DIR}/../lib/ct-matrix-auth.sh"

# Fetch joined rooms
ROOMS=$(curl -sf "${MATRIX_HOMESERVER}/_matrix/client/v3/joined_rooms" \
  -H "Authorization: Bearer ${MATRIX_TOKEN}" \
  | python3 -c "import json,sys; [print(r) for r in sorted(json.load(sys.stdin)['joined_rooms'])]")

printf "%-45s  %s\n" "Room ID" "Name"
printf "%s\n" "----------------------------------------------------------------------"

while IFS= read -r room_id; do
  name=$(curl -sf \
    "${MATRIX_HOMESERVER}/_matrix/client/v3/rooms/$(matrix_url_encode "$room_id")/state/m.room.name" \
    -H "Authorization: Bearer ${MATRIX_TOKEN}" \
    2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('name',''))" 2>/dev/null \
    || echo "(no name)")
  printf "%-45s  %s\n" "$room_id" "${name:-(no name)}"
done <<< "$ROOMS"
