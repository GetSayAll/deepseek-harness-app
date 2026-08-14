#!/usr/bin/env bash
set -euo pipefail

EXECUTABLE_NAME="DeepSeekHarness"
APP_DISPLAY_NAME="DS Harness"
BUNDLE_ID="app.sayall.ds-app"
APP_VERSION="${APP_VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="14.0"
NODE_VERSION="${NODE_VERSION:-v24.19.0}"

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
DIST_DIR="$APP_ROOT/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
RUNTIME_ROOT="$APP_RESOURCES/runtime"
RUNTIME_APP="$RUNTIME_ROOT/app"
NODE_CACHE="$APP_ROOT/.cache/node"
ICON_SOURCE="$APP_ROOT/Resources/AppIcon.png"
WORKSPACE_STATE="$REPOSITORY_ROOT/node_modules/.pnpm-workspace-state-v1.json"
STATE_BACKUP="$(mktemp "${TMPDIR:-/tmp}/dsh-pnpm-state.XXXXXX")"
SMOKE_ROOT=""

restore_workspace_state() {
  if [[ -s "$STATE_BACKUP" ]]; then cp "$STATE_BACKUP" "$WORKSPACE_STATE"; fi
  rm -f "$STATE_BACKUP"
  if [[ -n "$SMOKE_ROOT" ]]; then rm -rf "$SMOKE_ROOT"; fi
}
trap restore_workspace_state EXIT

if [[ ! -f "$WORKSPACE_STATE" ]]; then
  echo "missing pnpm workspace state; run pnpm install before packaging" >&2
  exit 1
fi
cp "$WORKSPACE_STATE" "$STATE_BACKUP"

case "$(uname -m)" in
  arm64) NODE_ARCH="arm64" ;;
  x86_64) NODE_ARCH="x64" ;;
  *) echo "unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

NODE_ARCHIVE="node-$NODE_VERSION-darwin-$NODE_ARCH.tar.gz"
NODE_URL="https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE"
NODE_ARCHIVE_PATH="$NODE_CACHE/$NODE_ARCHIVE"
NODE_EXTRACTED="$NODE_CACHE/node-$NODE_VERSION-darwin-$NODE_ARCH"

cd "$REPOSITORY_ROOT"
PNPM_REPOSITORY_ARGS=(
  --config.enable-global-virtual-store=false
  --config.node-linker=isolated
  --config.verify-deps-before-run=error
)
pnpm "${PNPM_REPOSITORY_ARGS[@]}" run build:lib:host
pnpm "${PNPM_REPOSITORY_ARGS[@]}" --filter @deepseek-ai/dsh-macos run build:host

cd "$APP_ROOT"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$RUNTIME_APP" "$NODE_CACHE"
cp "$BUILD_BINARY" "$APP_MACOS/$EXECUTABLE_NAME"
strip -S -x "$APP_MACOS/$EXECUTABLE_NAME"
chmod +x "$APP_MACOS/$EXECUTABLE_NAME"

ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/dsh-app-icon.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/AppIcon.icns"

cd "$REPOSITORY_ROOT"
CI=true pnpm --config.node-linker=hoisted --config.package-import-method=copy \
  --filter @deepseek-ai/dsh-macos deploy --legacy --prod "$RUNTIME_APP"
node "$APP_ROOT/scripts/complete-runtime-workspace-closure.mjs" "$REPOSITORY_ROOT" "$RUNTIME_APP"
find "$RUNTIME_APP/node_modules" -type d -name .bin -prune -exec rm -rf {} +
rm -rf "$RUNTIME_APP/node_modules/.pnpm"
rm -f "$RUNTIME_APP/node_modules/.modules.yaml"
find "$RUNTIME_APP/node_modules/@deepseek-ai" -type f \
  \( -path '*/lib/client.js' -o -path '*/lib/client.js.map' \) -delete
# pnpm deploy can retain workspace hard links even with copy imports. Replace
# every multi-link file so later workspace builds cannot mutate the app bundle.
find "$RUNTIME_APP" -type f -links +1 -exec sh -c '
  for file do
    cp -p "$file" "$file.dsh-copy"
    mv -f "$file.dsh-copy" "$file"
  done
' sh {} +
find "$RUNTIME_APP/node_modules/node-pty/prebuilds" -mindepth 1 -maxdepth 1 -type d \
  ! -name "darwin-$NODE_ARCH" -exec rm -rf {} +

if [[ ! -f "$NODE_ARCHIVE_PATH" ]]; then
  curl -fL "$NODE_URL" -o "$NODE_ARCHIVE_PATH"
fi
curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" \
  | grep " $NODE_ARCHIVE\$" \
  | (cd "$NODE_CACHE" && shasum -a 256 -c -)
if [[ ! -x "$NODE_EXTRACTED/bin/node" ]]; then
  rm -rf "$NODE_EXTRACTED"
  tar -xzf "$NODE_ARCHIVE_PATH" -C "$NODE_CACHE"
fi
mkdir -p "$RUNTIME_ROOT/node/bin"
cp "$NODE_EXTRACTED/bin/node" "$RUNTIME_ROOT/node/bin/node"
cp "$NODE_EXTRACTED/LICENSE" "$RUNTIME_ROOT/node/LICENSE"
chmod +x "$RUNTIME_ROOT/node/bin/node"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-package.XXXXXX")"
cat >"$SMOKE_ROOT/input.ndjson" <<'NDJSON'
{"id":"h","type":"hello","protocolVersion":0}
{"id":"s","type":"shutdown"}
NDJSON
(cd "$SMOKE_ROOT" && HOME="$SMOKE_ROOT/home" "$RUNTIME_ROOT/node/bin/node" "$RUNTIME_APP/lib/sidecar.js" \
  <"$SMOKE_ROOT/input.ndjson" >"$SMOKE_ROOT/output.ndjson")
node - "$SMOKE_ROOT/output.ndjson" <<'NODE'
const { readFileSync } = require('node:fs')
const frames = readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse)
if (frames[0]?.id !== 'h' || frames[0]?.type !== 'hello' || frames[0]?.protocolVersion !== 0) {
  throw new Error('packaged sidecar did not negotiate protocol version 0')
}
if (frames[1]?.id !== 's' || frames[1]?.type !== 'response' || frames[1]?.value === undefined) {
  throw new Error('packaged sidecar did not acknowledge shutdown')
}
NODE

if [[ -n "$(rg -a -l -F "$REPOSITORY_ROOT" "$APP_BUNDLE")" ]]; then
  echo "packaged application contains an absolute repository path" >&2
  exit 1
fi
if find "$APP_BUNDLE" -type l -print -quit | grep -q .; then
  echo "packaged application contains symbolic links" >&2
  exit 1
fi
if find "$RUNTIME_APP" -type f -links +1 -print -quit | grep -q .; then
  echo "packaged native runtime contains hard-linked files" >&2
  exit 1
fi
if find "$RUNTIME_APP/node_modules/@deepseek-ai" -type f \
  \( -path '*/lib/client.js' -o -path '*/lib/client.js.map' \) -print -quit | grep -q .; then
  echo "packaged native runtime contains disabled browser entry artifacts" >&2
  exit 1
fi

echo "$APP_BUNDLE"
