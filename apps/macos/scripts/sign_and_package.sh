#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_NAME="DeepSeekHarness"
APP_DISPLAY_NAME="DS Harness"
ASSET_NAME="DS-Harness"
APP_VERSION="${APP_VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:?BUILD_NUMBER is required}"
RELEASE_TAG="${RELEASE_TAG:-v$APP_VERSION}"

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$APP_ROOT/dist/$APP_DISPLAY_NAME.app}"
RELEASE_DIR="${RELEASE_DIR:-$APP_ROOT/dist/release}"
DMG_PATH="$RELEASE_DIR/$ASSET_NAME-$APP_VERSION-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
UPDATE_ZIP="$RELEASE_DIR/$ASSET_NAME-$APP_VERSION-arm64.zip"
APPCAST_PATH="$RELEASE_DIR/appcast.xml"
NODE_ENTITLEMENTS="$APP_ROOT/Resources/Node.entitlements"
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
DERIVE_SPARKLE_PUBLIC_KEY="$APP_ROOT/scripts/derive_sparkle_public_key.mjs"
GENERATE_APPCAST="$APP_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SIGN_UPDATE="$APP_ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"
DOWNLOAD_PREFIX="https://github.com/GetSayAll/deepseek-harness-app/releases/download/$RELEASE_TAG/"
RELEASE_PAGE="https://github.com/GetSayAll/deepseek-harness-app/releases/tag/$RELEASE_TAG"
NOTARIZE=false
ENTITLEMENTS_OUTPUT=""
SMOKE_ROOT=""

cleanup() {
  if [[ -n "$ENTITLEMENTS_OUTPUT" ]]; then rm -f -- "$ENTITLEMENTS_OUTPUT"; fi
  if [[ -n "$SMOKE_ROOT" ]]; then rm -rf -- "$SMOKE_ROOT"; fi
}

trap cleanup EXIT

if [[ "${1:-}" == "--notarize" ]]; then NOTARIZE=true; shift; fi
if [[ $# -ne 0 ]]; then
  echo "usage: $0 [--notarize]" >&2
  exit 2
fi
case "$BUILD_NUMBER" in
  ''|*[!0-9]*|0)
    echo "BUILD_NUMBER must be a positive integer" >&2
    exit 1
    ;;
esac

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing application bundle: $APP_BUNDLE" >&2
  exit 1
fi
if [[ "$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")" != "$APP_VERSION" ]]; then
  echo "application version does not match APP_VERSION=$APP_VERSION" >&2
  exit 1
fi
APP_BUILD="$(plutil -extract CFBundleVersion raw "$APP_BUNDLE/Contents/Info.plist")"
if [[ "$APP_BUILD" != "$BUILD_NUMBER" ]]; then
  echo "application build does not match BUILD_NUMBER=$BUILD_NUMBER" >&2
  exit 1
fi
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "application bundle is missing Sparkle.framework" >&2
  exit 1
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-${SIGN_IDENTITY:-$(security find-identity -p codesigning -v \
  | awk -F'"' '/Developer ID Application:/ { print $2; exit }')}}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "no Developer ID Application identity is available" >&2
  exit 1
fi
if $NOTARIZE && [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOTARY_PROFILE is required with --notarize" >&2
  exit 1
fi
if $NOTARIZE; then
  SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:?SPARKLE_PRIVATE_KEY_FILE is required with --notarize}"
  SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required with --notarize}"
  RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:?RELEASE_NOTES_FILE is required with --notarize}"
  if [[ ! -r "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    echo "Sparkle private key file is not readable" >&2
    exit 1
  fi
  if [[ ! -r "$RELEASE_NOTES_FILE" ]]; then
    echo "release notes file is not readable" >&2
    exit 1
  fi
  if [[ ! -r "$DERIVE_SPARKLE_PUBLIC_KEY" \
    || ! -x "$GENERATE_APPCAST" || ! -x "$SIGN_UPDATE" ]]; then
    echo "Sparkle release tools are unavailable; resolve Swift package dependencies first" >&2
    exit 1
  fi

  if ! DERIVED_SPARKLE_PUBLIC_KEY="$(node "$DERIVE_SPARKLE_PUBLIC_KEY" \
    "$SPARKLE_PRIVATE_KEY_FILE" 2>/dev/null)"; then
    echo "Sparkle public-key derivation failed" >&2
    exit 1
  fi
  if [[ -z "$DERIVED_SPARKLE_PUBLIC_KEY" ]]; then
    echo "Sparkle public-key derivation returned no key" >&2
    exit 1
  fi
  if [[ "$DERIVED_SPARKLE_PUBLIC_KEY" != "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "Sparkle private and public keys do not match" >&2
    exit 1
  fi

  APP_SPARKLE_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw \
    "$APP_BUNDLE/Contents/Info.plist")"
  if [[ "$APP_SPARKLE_PUBLIC_KEY" != "$DERIVED_SPARKLE_PUBLIC_KEY" ]]; then
    echo "application Sparkle public key does not match the release key" >&2
    exit 1
  fi
fi
SIGNING_KEYCHAIN_ARGS=()
NOTARY_KEYCHAIN_ARGS=()
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  SIGNING_KEYCHAIN_ARGS=(--keychain "$NOTARY_KEYCHAIN")
  NOTARY_KEYCHAIN_ARGS=(--keychain "$NOTARY_KEYCHAIN")
fi

sign_macho() {
  local path="$1"
  codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
    --sign "$SIGN_IDENTITY" "$path"
}

while IFS= read -r -d '' path; do
  [[ "$path" == "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" ]] && continue
  [[ "$path" == "$APP_BUNDLE/Contents/Resources/runtime/node/bin/node" ]] && continue
  [[ "$path" == "$SPARKLE_FRAMEWORK/"* ]] && continue
  if file "$path" | grep -q 'Mach-O'; then sign_macho "$path"; fi
done < <(find "$APP_BUNDLE" -type f \( -perm -111 -o -name '*.node' -o -name '*.dylib' \) -print0)

codesign --force --options runtime --timestamp --entitlements "$NODE_ENTITLEMENTS" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/Resources/runtime/node/bin/node"
codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
  "${SIGNING_KEYCHAIN_ARGS[@]}" --sign "$SIGN_IDENTITY" \
  "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION_DIR/Autoupdate"
codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$SPARKLE_VERSION_DIR/Updater.app"
codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK"
codesign --force --options runtime --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ENTITLEMENTS_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/dsh-node-entitlements.XXXXXX")"
codesign -d --entitlements :- \
  "$APP_BUNDLE/Contents/Resources/runtime/node/bin/node" >"$ENTITLEMENTS_OUTPUT" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.allow-jit' "$ENTITLEMENTS_OUTPUT" | grep -qx true; then
  echo "signed Node runtime is missing the JIT entitlement" >&2
  exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_OUTPUT" >/dev/null 2>&1; then
  echo "signed Node runtime contains the debug entitlement" >&2
  exit 1
fi

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dsh-signed-app.XXXXXX")"
mkdir -p "$SMOKE_ROOT/home"
printf '%s\n%s\n' \
  '{"id":"h","type":"hello","protocolVersion":0}' \
  '{"id":"s","type":"shutdown"}' >"$SMOKE_ROOT/input.ndjson"
(cd "$SMOKE_ROOT" && HOME="$SMOKE_ROOT/home" \
  "$APP_BUNDLE/Contents/Resources/runtime/node/bin/node" \
  "$APP_BUNDLE/Contents/Resources/runtime/app/lib/sidecar.js" \
  <"$SMOKE_ROOT/input.ndjson" >"$SMOKE_ROOT/output.ndjson")
node - "$SMOKE_ROOT/output.ndjson" <<'NODE'
const { readFileSync } = require('node:fs')
const frames = readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse)
if (frames[0]?.type !== 'hello' || frames[0]?.protocolVersion !== 0 || frames[1]?.type !== 'response') {
  throw new Error('signed application sidecar smoke failed')
}
NODE

mkdir -p "$RELEASE_DIR"
if $NOTARIZE; then
  APP_ZIP="$SMOKE_ROOT/$ASSET_NAME.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" \
    "${NOTARY_KEYCHAIN_ARGS[@]}" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vv --type execute "$APP_BUNDLE"
fi

DMG_ROOT="$SMOKE_ROOT/dmg"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_DISPLAY_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGN_IDENTITY" "$DMG_PATH"

if $NOTARIZE; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" \
    "${NOTARY_KEYCHAIN_ARGS[@]}" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"
fi

(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$CHECKSUM_PATH")")

if $NOTARIZE; then
  SPARKLE_ARCHIVES="$SMOKE_ROOT/sparkle-archives"
  UPDATE_BASENAME="$(basename "$UPDATE_ZIP")"
  mkdir -p "$SPARKLE_ARCHIVES"
  rm -f "$UPDATE_ZIP" "$APPCAST_PATH"
  ditto -c -k --keepParent "$APP_BUNDLE" "$UPDATE_ZIP"
  ditto --norsrc --noqtn --noacl "$UPDATE_ZIP" "$SPARKLE_ARCHIVES/$UPDATE_BASENAME"
  ditto --norsrc --noqtn --noacl \
    "$RELEASE_NOTES_FILE" "$SPARKLE_ARCHIVES/${UPDATE_BASENAME%.zip}.md"
  "$GENERATE_APPCAST" \
    --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --link "$RELEASE_PAGE" \
    --versions "$APP_BUILD" \
    --maximum-versions 1 \
    --embed-release-notes \
    -o "$APPCAST_PATH" \
    "$SPARKLE_ARCHIVES"

  ENCLOSURE_SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$APPCAST_PATH" | head -n 1)"
  if [[ -z "$ENCLOSURE_SIGNATURE" ]]; then
    echo "generated appcast is missing an enclosure signature" >&2
    exit 1
  fi
  rg -Fq "url=\"$DOWNLOAD_PREFIX$UPDATE_BASENAME\"" "$APPCAST_PATH"
  rg -Fq "<sparkle:version>$APP_BUILD</sparkle:version>" "$APPCAST_PATH"
  rg -Fq '<description>' "$APPCAST_PATH"
  "$SIGN_UPDATE" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    "$UPDATE_ZIP" "$ENCLOSURE_SIGNATURE"
  "$SIGN_UPDATE" --verify --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" "$APPCAST_PATH"
fi
echo "$DMG_PATH"
