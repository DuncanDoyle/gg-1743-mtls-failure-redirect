#!/bin/bash
# Shows the TLS session resumption limitation in a real browser (Chromium in Docker, valid client cert).
# Same overrides as curl-request.sh: GW_IP, HTTPS_PORT, HTTP_PORT. DOCKER_NETWORK picks the container network.

cd "$(dirname "$0")"

HTTPS_PORT="${HTTPS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
PLAYWRIGHT_VERSION="1.49.1"

# The browser runs in a container, so a gateway on the host's loopback is reached via host.docker.internal.
GW_HOST="${GW_IP:-127.0.0.1}"
case "$GW_HOST" in
  127.*|localhost) GW_HOST="host.docker.internal" ;;
esac

if [ "$HTTPS_PORT" = "443" ]; then
  API_ORIGIN="https://api.example.com"
else
  API_ORIGIN="https://api.example.com:${HTTPS_PORT}"
fi

docker run --rm --network "${DOCKER_NETWORK:-bridge}" --add-host host.docker.internal:host-gateway \
  -v "$PWD/browser-test:/test:ro" -v "$PWD/certs:/certs:ro" \
  -e API_URL="${API_ORIGIN}/get" \
  -e GW_HOST="$GW_HOST" \
  -e API_ORIGIN="$API_ORIGIN" \
  "mcr.microsoft.com/playwright:v${PLAYWRIGHT_VERSION}-noble" bash -c '
    set -e
    apt-get -qq update >/dev/null && apt-get -qq install -y libnss3-tools >/dev/null 2>&1
    # Trust the CA and import the valid client cert into the browser (NSS) cert store.
    DB=sql:$HOME/.pki/nssdb && mkdir -p $HOME/.pki/nssdb
    certutil -N --empty-password -d $DB
    certutil -A -n gg-1743-ca -t "C,," -i /certs/ca.crt -d $DB
    pk12util -i /certs/client.p12 -W password -d $DB >/dev/null
    # Chrome policy: send the client cert to the API without a certificate picker.
    mkdir -p /etc/chromium/policies/managed
    node -e "const p = {pattern: process.env.API_ORIGIN, filter: {}};
      console.log(JSON.stringify({AutoSelectCertificateForUrls: [JSON.stringify(p)]}))" \
      > /etc/chromium/policies/managed/client-cert.json
    cp /test/browser-test.mjs /tmp/ && cd /tmp && npm install --silent playwright@'"$PLAYWRIGHT_VERSION"' >/dev/null 2>&1
    # Chromium does not resolve host.docker.internal in its own resolver, so map to the IP.
    GW_ADDR=$(getent hosts "$GW_HOST" | awk "{print \$1; exit}"); GW_ADDR=${GW_ADDR:-$GW_HOST}
    export HOST_RULES="MAP api.example.com $GW_ADDR, MAP diary.example.com $GW_ADDR"
    node browser-test.mjs'
