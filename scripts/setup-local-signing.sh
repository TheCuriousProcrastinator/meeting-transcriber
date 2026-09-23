#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Reuse the signing identity/keychain definitions already used by the
# MeetingTranscriber E2E signing infrastructure.
# shellcheck source=lib/signing.sh
source "$SCRIPT_DIR/lib/signing.sh"

CERT_NAME="$DEV_CERT_NAME"
KEYCHAIN="$DEV_KEYCHAIN"
KEYCHAIN_PASS=""

CERT_DIR="$HOME/Library/Application Support/MeetingTranscriber/signing"
CERT_PATH="$CERT_DIR/local-code-signing.crt"

log()  { printf '[local-signing] %s\n' "$*"; }
fail() { printf '[local-signing] FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$CERT_DIR"
chmod 0700 "$CERT_DIR"

# If the dedicated keychain already exists, keep it. Never silently rotate
# the certificate because doing so would invalidate the TCC identity again.
if [ -f "$KEYCHAIN" ]; then
    security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN" 2>/dev/null || true
    "$SCRIPT_DIR/keychain-prepend.sh" "$KEYCHAIN"
fi

if [ -f "$KEYCHAIN" ] \
    && security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" >/dev/null 2>&1
then
    log "Existing certificate found - keeping it."
    security find-certificate \
        -c "$CERT_NAME" \
        -p "$KEYCHAIN" \
        > "$CERT_PATH" \
        || fail "could not export existing certificate"
else
    if [ -f "$KEYCHAIN" ]; then
        fail "$KEYCHAIN exists but does not contain '$CERT_NAME'. Refusing to replace it automatically."
    fi

    log "Creating stable self-signed Code Signing identity '$CERT_NAME'."

    TMPD="$(mktemp -d)"
    trap 'rm -rf "$TMPD"' EXIT

    openssl req \
        -x509 \
        -nodes \
        -newkey rsa:2048 \
        -days 3650 \
        -subj "/CN=$CERT_NAME/O=meetingtranscriber-local" \
        -keyout "$TMPD/cert.key" \
        -out "$TMPD/cert.crt" \
        -addext "keyUsage = critical, digitalSignature" \
        -addext "extendedKeyUsage = critical, codeSigning" \
        -addext "basicConstraints = critical, CA:false" \
        >/dev/null 2>&1 \
        || fail "openssl certificate creation failed"

    PKCS12_ARGS=(-export)
    if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
        PKCS12_ARGS+=(-legacy)
        log "PKCS#12: OpenSSL 3 legacy mode"
    else
        log "PKCS#12: LibreSSL/native compatibility mode"
    fi

    openssl pkcs12 "${PKCS12_ARGS[@]}" \
        -inkey "$TMPD/cert.key" \
        -in "$TMPD/cert.crt" \
        -name "$CERT_NAME" \
        -passout pass:dev \
        -out "$TMPD/cert.p12" \
        || fail "PKCS#12 creation failed"

    log "Creating dedicated keychain at $KEYCHAIN"

    security create-keychain \
        -p "$KEYCHAIN_PASS" \
        "$KEYCHAIN" \
        || fail "could not create dedicated keychain"

    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"

    "$SCRIPT_DIR/keychain-prepend.sh" "$KEYCHAIN"

    security import "$TMPD/cert.p12" \
        -k "$KEYCHAIN" \
        -P dev \
        -A \
        -t agg \
        || fail "could not import signing identity"

    security set-key-partition-list \
        -S "apple-tool:,apple:,codesign:" \
        -s \
        -k "$KEYCHAIN_PASS" \
        "$KEYCHAIN" \
        >/dev/null \
        || fail "could not allow codesign to use private key"

    cp "$TMPD/cert.crt" "$CERT_PATH"
    chmod 0600 "$CERT_PATH"

    rm -rf "$TMPD"
    trap - EXIT
fi

# The certificate has to be trusted for the Code Signing policy.
if [ -z "$(dev_signing_identity)" ]; then
    echo
    log "macOS will now ask for Touch ID or your password once."
    log "This adds per-user trust for this local Code Signing certificate."

    security add-trusted-cert \
        -r trustRoot \
        -p codeSign \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        "$CERT_PATH" \
        || fail "could not add Code Signing trust"
fi

IDENTITY="$(dev_signing_identity)"

[ -n "$IDENTITY" ] || {
    fail "certificate exists but is still not a valid Code Signing identity"
}

echo
log "READY"
log "Certificate: $CERT_NAME"
log "SHA-1:       $IDENTITY"
log "Keychain:    $KEYCHAIN"
