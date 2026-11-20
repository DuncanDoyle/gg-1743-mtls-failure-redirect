#!/bin/sh
# Generates the server cert, a trusted client cert and a "rogue" client cert signed by an untrusted CA.
set -e

cd "$(dirname "$0")/.."
mkdir -p certs
cd certs

# Self-signed CA: <name> <CN>
create_ca() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout "$1.key" -out "$1.crt" -subj "/O=gg-1743/CN=$2" 2>/dev/null
}

# Leaf cert signed by a CA: <name> <CN> <ca-name> <extensions>
create_cert() {
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "/O=gg-1743/CN=$2" 2>/dev/null
  printf '%s\n' "$4" > "$1.ext"
  openssl x509 -req -in "$1.csr" -CA "$3.crt" -CAkey "$3.key" -CAcreateserial -days 365 -out "$1.crt" -extfile "$1.ext" 2>/dev/null
  rm -f "$1.csr" "$1.ext"
}

printf "\nGenerate CAs ...\n"
create_ca ca "Mutual Trust CA"            # Trusted by the Gateway.
create_ca rogue-ca "Totally Legit CA"     # NOT trusted by the Gateway.

printf "\nGenerate server and client certificates ...\n"
create_cert server api.example.com ca "subjectAltName=DNS:api.example.com
extendedKeyUsage=serverAuth"
create_cert client "valid-client" ca "extendedKeyUsage=clientAuth"
create_cert rogue-client "rogue-client" rogue-ca "extendedKeyUsage=clientAuth"

# PKCS#12 bundle (password: "password") to import the valid client cert into a browser.
openssl pkcs12 -export -legacy -in client.crt -inkey client.key -out client.p12 -passout pass:password 2>/dev/null \
  || openssl pkcs12 -export -in client.crt -inkey client.key -out client.p12 -passout pass:password

ls -1 "$PWD"
