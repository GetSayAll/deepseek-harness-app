#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_NAME="DeepSeekHarness"
APP_DISPLAY_NAME="DS Harness"
ASSET_NAME="DS-Harness"
APP_VERSION="${APP_VERSION:-0.1.1}"

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${APP_BUNDLE:-$APP_ROOT/dist/$APP_DISPLAY_NAME.app}"
RELEASE_DIR="${RELEASE_DIR:-$APP_ROOT/dist/release}"
DMG_PATH="$RELEASE_DIR/$ASSET_NAME-$APP_VERSION-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
NODE_ENTITLEMENTS="$APP_ROOT/Resources/Node.entitlements"
NOTARIZE=false

if [[ "${1:-}" == "--notarize" ]]; then NOTARIZE=true; shift; fi
if [[ $# -ne 0 ]]; then
  echo "usage: $0 [--notarize]" >&2
  exit 2
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing application bundle: $APP_BUNDLE" >&2
  exit 1
fi
if [[ "$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")" != "$APP_VERSION" ]]; then
  echo "application version does not match APP_VERSION=$APP_VERSION" >&2
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
  if file "$path" | grep -q 'Mach-O'; then sign_macho "$path"; fi
done < <(find "$APP_BUNDLE" -type f \( -perm -111 -o -name '*.node' -o -name '*.dylib' \) -print0)

codesign --force --options runtime --timestamp --entitlements "$NODE_ENTITLEMENTS" \
  "${SIGNING_KEYCHAIN_ARGS[@]}" --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE/Contents/Resources/runtime/node/bin/node"
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
trap 'rm -rf "$SMOKE_ROOT" "$ENTITLEMENTS_OUTPUT"' EXIT
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
echo "$DMG_PATH"
