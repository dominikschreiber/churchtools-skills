# ct-matrix-auth.sh — shared ChurchTools→Matrix authentication
#
# Source this file (do not execute it directly). Requires:
#   CHURCHTOOLS_BASE_URL      e.g. https://your-instance.church.tools
#   CHURCHTOOLS_LOGIN_TOKEN   API login token
#
# Optional:
#   MATRIX_HOMESERVER         defaults to https://chat.church.tools
#
# After sourcing, the following are exported:
#   MATRIX_TOKEN       Matrix access token
#   MATRIX_USER        @ct_<guid-lowercase>:<homeserver-host>
#   MATRIX_HOMESERVER  normalised homeserver URL
#   HOMESERVER_HOST    host only, no protocol
#   PERSON_ID          ChurchTools person ID
#   PERSON_GUID        ChurchTools person GUID
#
# Also defines helper:
#   matrix_url_encode <string>   percent-encodes a string (e.g. a room ID)

: "${CHURCHTOOLS_BASE_URL:?CHURCHTOOLS_BASE_URL is required}"
: "${CHURCHTOOLS_LOGIN_TOKEN:?CHURCHTOOLS_LOGIN_TOKEN is required}"
MATRIX_HOMESERVER="${MATRIX_HOMESERVER:-https://chat.church.tools}"

_ct_whoami=$(curl -sf "${CHURCHTOOLS_BASE_URL}/api/whoami?login_token=${CHURCHTOOLS_LOGIN_TOKEN}")
PERSON_ID=$(echo "$_ct_whoami" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])")
PERSON_GUID=$(echo "$_ct_whoami" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['guid'])")
unset _ct_whoami

_ct_matrix_password=$(curl -sf \
  "${CHURCHTOOLS_BASE_URL}/api/persons/${PERSON_ID}/logintoken?login_token=${CHURCHTOOLS_LOGIN_TOKEN}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data'])")

HOMESERVER_HOST=$(echo "$MATRIX_HOMESERVER" | sed 's|^https://||; s|^http://||')
MATRIX_USER="@ct_$(echo "$PERSON_GUID" | tr '[:upper:]' '[:lower:]'):${HOMESERVER_HOST}"

MATRIX_TOKEN=$(curl -sf "${MATRIX_HOMESERVER}/_matrix/client/v3/login" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"m.login.password\",\"user\":\"${MATRIX_USER}\",\"password\":\"${_ct_matrix_password}\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
unset _ct_matrix_password

export MATRIX_TOKEN MATRIX_USER MATRIX_HOMESERVER HOMESERVER_HOST PERSON_ID PERSON_GUID

matrix_url_encode() {
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}
