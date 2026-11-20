#!/bin/bash
# Checks the mTLS failure redirect. Overrides: GW_IP (adds --resolve), HTTPS_PORT, HTTP_PORT,
# DIARY_URL (must match the value used by install/setup.sh).

cd "$(dirname "$0")"

HTTPS_PORT="${HTTPS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
API_URL="https://api.example.com:${HTTPS_PORT}/get"
if [ "$HTTP_PORT" = "80" ]; then
  DIARY_URL="${DIARY_URL:-http://diary.example.com}"
else
  DIARY_URL="${DIARY_URL:-http://diary.example.com:${HTTP_PORT}}"
fi

RESOLVE=()
if [ -n "$GW_IP" ]; then
  RESOLVE=(--resolve "api.example.com:${HTTPS_PORT}:${GW_IP}" --resolve "diary.example.com:${HTTP_PORT}:${GW_IP}")
fi

FAILED=0
LOCATION=""

# check <name> <expected status> <expected Location, or ""> -- <curl args...>
check() {
  local name="$1" want_code="$2" want_location="$3"
  shift 4
  local out code
  out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "${RESOLVE[@]}" --cacert certs/ca.crt "$@")
  code="${out%% *}"
  LOCATION="${out#* }"
  if [ "$code" = "$want_code" ] && [ "$LOCATION" = "$want_location" ]; then
    printf "PASS  %-28s expected %s %s, got %s %s\n" "$name" "$want_code" "$want_location" "$code" "$LOCATION"
  else
    printf "FAIL  %-28s expected %s %s, got %s %s\n" "$name" "$want_code" "$want_location" "$code" "$LOCATION"
    FAILED=1
  fi
}

check "1. valid client cert" 200 "" -- --cert certs/client.crt --key certs/client.key "$API_URL"
check "2. no client cert" 302 "${DIARY_URL}/?reason=no-cert" -- "$API_URL"
REDIRECT="$LOCATION"
check "3. rogue client cert" 302 "${DIARY_URL}/?reason=invalid-cert" -- --cert certs/rogue-client.crt --key certs/rogue-client.key "$API_URL"

# Follow the redirect from check 2: the diary must load without a client cert, or the redirect would loop.
if [ -n "$REDIRECT" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' "${RESOLVE[@]}" "$REDIRECT")" = "200" ] \
    && curl -s "${RESOLVE[@]}" "$REDIRECT" | grep -q "Dear diary"; then
  printf "PASS  %-28s diary page served at %s\n" "4. diary page" "$REDIRECT"
else
  printf "FAIL  %-28s diary page not served at %s\n" "4. diary page" "${REDIRECT:-<no redirect>}"
  FAILED=1
fi

# Known limitation: Envoy doesn't re-validate the client cert on TLS session resumption, so
# peer_certificate_valid is false and a valid client gets redirected. Informational, doesn't fail the run.
OPENSSL="${OPENSSL:-openssl}"
SESSION=$(mktemp)
resumed_request() {
  printf 'GET /get HTTP/1.1\r\nHost: api.example.com\r\nConnection: close\r\n\r\n' \
    | "$OPENSSL" s_client -connect "${GW_IP:-api.example.com}:${HTTPS_PORT}" -servername api.example.com \
        -CAfile certs/ca.crt -cert certs/client.crt -key certs/client.key -ign_eof "$@" 2>/dev/null \
    | grep -a -o -E '^(New|Reused),|HTTP/1.1 [0-9]{3}|reason=[a-z-]+' | tr '\n' ' '
}
if "$OPENSSL" version | grep -q LibreSSL; then
  printf "SKIP  %-28s needs OpenSSL, not LibreSSL (e.g. OPENSSL=/opt/homebrew/bin/openssl)\n" "5. session resumption"
else
  for tls in -tls1_2 -tls1_3; do
    rm -f "$SESSION"
    first=$(resumed_request "$tls" -sess_out "$SESSION")
    second=$(resumed_request "$tls" -sess_in "$SESSION")
    printf "INFO  %-28s first: %s| second: %s\n" "5. valid cert, ${tls#-}" "$first" "$second"
  done
fi
rm -f "$SESSION"

exit $FAILED
