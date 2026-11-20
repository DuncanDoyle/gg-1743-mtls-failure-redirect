#!/bin/bash
# Checks the mTLS failure redirect. Overrides: GW_IP (adds --resolve), HTTPS_PORT, HTTP_PORT.

cd "$(dirname "$0")"

HTTPS_PORT="${HTTPS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
API_URL="https://api.example.com:${HTTPS_PORT}/get"
DIARY_PAGE="http://diary.example.com:${HTTP_PORT}/"

RESOLVE=()
if [ -n "$GW_IP" ]; then
  RESOLVE=(--resolve "api.example.com:${HTTPS_PORT}:${GW_IP}" --resolve "diary.example.com:${HTTP_PORT}:${GW_IP}")
fi

FAILED=0

# check <name> <expected status> <expected Location substring or ""> -- <curl args...>
check() {
  local name="$1" want_code="$2" want_location="$3"
  shift 4
  local out code location
  out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "${RESOLVE[@]}" --cacert certs/ca.crt "$@")
  code="${out%% *}"
  location="${out#* }"
  if [ "$code" = "$want_code" ] && [[ "$location" == *"$want_location"* ]]; then
    printf "PASS  %-28s expected %s %s, got %s %s\n" "$name" "$want_code" "$want_location" "$code" "$location"
  else
    printf "FAIL  %-28s expected %s %s, got %s %s\n" "$name" "$want_code" "$want_location" "$code" "$location"
    FAILED=1
  fi
}

check "1. valid client cert" 200 "" -- --cert certs/client.crt --key certs/client.key "$API_URL"
check "2. no client cert" 302 "reason=no-cert" -- "$API_URL"
check "3. rogue client cert" 302 "reason=invalid-cert" -- --cert certs/rogue-client.crt --key certs/rogue-client.key "$API_URL"

# The diary must load without a client cert, or the redirect would loop.
if curl -s "${RESOLVE[@]}" "${DIARY_PAGE}?reason=no-cert" | grep -q "Dear diary"; then
  printf "PASS  %-28s diary page served without a client cert\n" "4. diary page"
else
  printf "FAIL  %-28s diary page not served at %s\n" "4. diary page" "$DIARY_PAGE"
  FAILED=1
fi

exit $FAILED
