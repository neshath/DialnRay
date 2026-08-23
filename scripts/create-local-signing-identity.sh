#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
IDENTITY_NAME="DialnRay Local Development"
LOGIN_KEYCHAIN="/Users/tinkerspace/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -Fq "\"${IDENTITY_NAME}\""; then
  echo "${IDENTITY_NAME} already exists."
  exit 0
fi

CERT_DIR=$(mktemp -d /private/tmp/dialnray-signing.XXXXXX)
PRIVATE_KEY="${CERT_DIR}/private-key.pem"
CERTIFICATE="${CERT_DIR}/certificate.pem"
ARCHIVE="${CERT_DIR}/identity.p12"
ARCHIVE_PASSWORD=$(openssl rand -hex 24)

cleanup() {
  rm -f "${PRIVATE_KEY}" "${CERTIFICATE}" "${ARCHIVE}"
  rmdir "${CERT_DIR}"
}
trap cleanup EXIT

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -days 3650 \
  -nodes \
  -config "${SCRIPT_DIR}/local-signing-openssl.cnf" \
  -keyout "${PRIVATE_KEY}" \
  -out "${CERTIFICATE}"

openssl pkcs12 \
  -export \
  -legacy \
  -name "${IDENTITY_NAME}" \
  -inkey "${PRIVATE_KEY}" \
  -in "${CERTIFICATE}" \
  -out "${ARCHIVE}" \
  -passout "pass:${ARCHIVE_PASSWORD}"

security import "${ARCHIVE}" \
  -k "${LOGIN_KEYCHAIN}" \
  -P "${ARCHIVE_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "${LOGIN_KEYCHAIN}" \
  "${CERTIFICATE}"

security find-identity -v -p codesigning
