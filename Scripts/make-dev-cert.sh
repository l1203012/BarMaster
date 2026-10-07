#!/bin/bash
# Creates a self-signed "BarMaster Dev" code-signing certificate in your login
# keychain, once. Scripts/build.sh signs with it automatically, which gives every
# build the same identity, so macOS remembers BarMaster's Accessibility and
# Automation permissions across rebuilds. macOS asks for your password to trust it.
#
#   Scripts/make-dev-cert.sh
set -euo pipefail

NAME="BarMaster Dev"
KEYCHAIN=~/Library/Keychains/login.keychain-db
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "✓ \"$NAME\" already exists"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -passout pass:barmaster -out "$TMP/cert.p12"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P barmaster -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
echo "✓ created \"$NAME\"; rebuild with Scripts/build.sh install"
