# Shared code-signing helpers for install-local.sh and release.sh.
# Expects ROOT_DIR to be set by the sourcing script.
# ensure_signing_identity resolves SIGNING_IDENTITY; sign_app_bundle applies it.

SIGNING_IDENTITY="${MAC_TWEAKS_SIGNING_IDENTITY:-}"
LOCAL_SIGNING_IDENTITY="${MAC_TWEAKS_LOCAL_SIGNING_IDENTITY:-Mac Tweaks Local Code Signing}"
SIGNING_DIR="$HOME/Library/Application Support/Mac Tweaks/Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

identity_exists() {
  local identity="$1"
  security find-identity -v -p codesigning 2>/dev/null | awk -F '"' -v name="$identity" '$2 == name { found = 1 } END { exit found ? 0 : 1 }'
}

apple_development_identity() {
  security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '$2 ~ /^Apple Development: / { print $2; exit }'
}

apple_development_certificate() {
  security find-certificate -a -c "Apple Development" -Z 2>/dev/null | awk -F '"' '/"alis"<blob>=/ { print $4; exit }'
}

create_local_signing_identity() {
  mkdir -p "$SIGNING_DIR"

  local key_file="$SIGNING_DIR/local-code-signing.key.pem"
  local cert_file="$SIGNING_DIR/local-code-signing.cert.pem"
  local p12_file="$SIGNING_DIR/local-code-signing.p12"
  local openssl_config="$SIGNING_DIR/local-code-signing.openssl.cnf"

  if [[ ! -f "$key_file" || ! -f "$cert_file" ]]; then
    cat > "$openssl_config" <<EOF
[ req ]
default_bits = 2048
prompt = no
distinguished_name = distinguished_name
x509_extensions = certificate_extensions

[ distinguished_name ]
CN = $LOCAL_SIGNING_IDENTITY

[ certificate_extensions ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

    openssl req \
      -new \
      -x509 \
      -newkey rsa:2048 \
      -sha256 \
      -days 3650 \
      -nodes \
      -keyout "$key_file" \
      -out "$cert_file" \
      -config "$openssl_config" >/dev/null 2>&1

    chmod 600 "$key_file"
  fi

  openssl pkcs12 \
    -export \
    -inkey "$key_file" \
    -in "$cert_file" \
    -out "$p12_file" \
    -name "$LOCAL_SIGNING_IDENTITY" \
    -passout "pass:" >/dev/null 2>&1
  chmod 600 "$p12_file"

  security import "$p12_file" -k "$LOGIN_KEYCHAIN" -P "" -A >/dev/null || true
  security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$cert_file" >/dev/null 2>&1 || true
}

ensure_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    if identity_exists "$SIGNING_IDENTITY"; then
      echo "Using requested signing identity: $SIGNING_IDENTITY"
      return
    fi

    echo "Requested signing identity was not found: $SIGNING_IDENTITY" >&2
    echo "Run 'security find-identity -v -p codesigning' to see available identities." >&2
    exit 1
  fi

  local apple_identity
  apple_identity="$(apple_development_identity)"
  if [[ -n "$apple_identity" ]]; then
    SIGNING_IDENTITY="$apple_identity"
    echo "Using Apple Development signing identity: $SIGNING_IDENTITY"
    return
  fi

  local apple_certificate
  apple_certificate="$(apple_development_certificate)"
  if [[ -n "$apple_certificate" ]]; then
    echo "Found Apple Development certificate, but it is not a usable signing identity: $apple_certificate" >&2
    echo "It is probably missing its private key. In Xcode > Settings > Accounts > Manage Certificates, create an Apple Development certificate from that screen, then rerun this script." >&2
    echo "Falling back to a stable local signing identity for this install." >&2
  fi

  SIGNING_IDENTITY="$LOCAL_SIGNING_IDENTITY"
  if identity_exists "$SIGNING_IDENTITY"; then
    echo "Using local signing identity: $SIGNING_IDENTITY"
    return
  fi

  echo "Creating local code signing identity: $SIGNING_IDENTITY"
  create_local_signing_identity

  if ! identity_exists "$SIGNING_IDENTITY"; then
    echo "Could not create a valid local code signing identity." >&2
    echo "Create a Code Signing certificate named '$SIGNING_IDENTITY' in Keychain Access, then rerun this script." >&2
    exit 1
  fi
}

sign_app_bundle() {
  local app_path="$1"
  local extension_path="$app_path/Contents/PlugIns/MacTweaksFinderExtension.appex"

  echo "Applying stable signature: $SIGNING_IDENTITY"
  find "$app_path/Contents" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' binary; do
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$binary"
  done
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --entitlements "$ROOT_DIR/FinderExtension/Resources/FinderExtension.entitlements" "$extension_path"
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$app_path"
  codesign --verify --deep --strict "$app_path"
}
