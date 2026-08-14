# macOS direct-download and Sparkle release reference

This reference applies only to the Apple silicon release lane under `apps/macos`. It does not change ordinary repository pull-request, stack, npm, Python, vendor, or native-package publication rules.

## Authority and release intent

Product changes reach `master` through ordinary pull requests. The coordinating agent alone creates and pushes candidate branches and tags, accesses release secrets, signs and notarizes artifacts, uploads assets, merges the candidate record, and changes GitHub Release state. Subagents research, plan, implement, test, and report without performing those mutations.

An unqualified release request selects a pre-release candidate. Stable promotion requires a separate explicit instruction naming an exact tag such as `v0.1.2`.

The available lane is an Apple silicon application for macOS 14 or later with Developer ID signing, notarization, direct-download DMG, Sparkle ZIP and appcast, and GitHub Releases delivery. Intel or universal binaries, PKG or App Store distribution, CDN delivery, and automated release-policy guards are not implemented.

## A. Prepare one candidate commit

Choose the version and build before creating the candidate. Derive the historical build floor from every non-draft arm64 DMG currently published by this repository, including pre-releases and failed candidates, so no public build can be reused. Each asset URL must be bound to its fixed tag, and each build is read from the mounted application's `CFBundleVersion`. The published `v0.1.1` artifact records build `1`, so the planned `v0.1.2` build is `2`; the executable check remains authoritative for later releases.

```sh
MACOS_VERSION=X.Y.Z
MACOS_BUILD=N
case "$MACOS_BUILD" in ''|*[!0-9]*|0) exit 1 ;; esac
MACOS_PUBLISHED_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-published.XXXXXX")"
MACOS_PUBLISHED_MOUNT=''
cleanup_published_builds() {
  if test -n "$MACOS_PUBLISHED_MOUNT"; then
    hdiutil detach "$MACOS_PUBLISHED_MOUNT" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$MACOS_PUBLISHED_ROOT"
}
trap cleanup_published_builds EXIT
gh api --paginate repos/GetSayAll/deepseek-harness-app/releases --jq '
  .[] | select(.draft == false) | .tag_name as $tag
  | .assets[]?
  | select(.name | test("^DS-Harness-[0-9]+\\.[0-9]+\\.[0-9]+-arm64\\.dmg$"))
  | [$tag, .name, .browser_download_url] | @tsv
' >"$MACOS_PUBLISHED_ROOT/releases.tsv"
test -s "$MACOS_PUBLISHED_ROOT/releases.tsv"
MACOS_HIGHEST_PUBLISHED_BUILD=0
while IFS="$(printf '\t')" read -r MACOS_PUBLISHED_TAG MACOS_PUBLISHED_ASSET MACOS_PUBLISHED_URL; do
  test "$MACOS_PUBLISHED_ASSET" = "DS-Harness-${MACOS_PUBLISHED_TAG#v}-arm64.dmg"
  test "$MACOS_PUBLISHED_URL" = "https://github.com/GetSayAll/deepseek-harness-app/releases/download/$MACOS_PUBLISHED_TAG/$MACOS_PUBLISHED_ASSET"
  MACOS_PUBLISHED_DMG="$MACOS_PUBLISHED_ROOT/$MACOS_PUBLISHED_ASSET"
  MACOS_ATTACH_PLIST="$MACOS_PUBLISHED_DMG.attach.plist"
  curl --fail --location --silent --show-error "$MACOS_PUBLISHED_URL" -o "$MACOS_PUBLISHED_DMG"
  hdiutil attach -readonly -nobrowse -plist "$MACOS_PUBLISHED_DMG" >"$MACOS_ATTACH_PLIST"
  MACOS_PUBLISHED_MOUNT="$(plutil -extract system-entities json -o - "$MACOS_ATTACH_PLIST" \
    | node -e "let s='';process.stdin.on('data',c=>s+=c).on('end',()=>{const p=JSON.parse(s).find(v=>v['mount-point'])?.['mount-point'];if(!p)process.exit(1);process.stdout.write(p)})")"
  MACOS_PUBLISHED_BUILD="$(plutil -extract CFBundleVersion raw \
    "$MACOS_PUBLISHED_MOUNT/DS Harness.app/Contents/Info.plist")"
  case "$MACOS_PUBLISHED_BUILD" in ''|*[!0-9]*|0) exit 1 ;; esac
  if (( 10#$MACOS_PUBLISHED_BUILD > MACOS_HIGHEST_PUBLISHED_BUILD )); then
    MACOS_HIGHEST_PUBLISHED_BUILD=$((10#$MACOS_PUBLISHED_BUILD))
  fi
  hdiutil detach "$MACOS_PUBLISHED_MOUNT"
  MACOS_PUBLISHED_MOUNT=''
done <"$MACOS_PUBLISHED_ROOT/releases.tsv"
test "$MACOS_HIGHEST_PUBLISHED_BUILD" -gt 0
test "$MACOS_BUILD" -gt "$MACOS_HIGHEST_PUBLISHED_BUILD"
cleanup_published_builds
trap - EXIT
```

Sparkle product changes and their resulting `apps/macos/Package.resolved` must already have entered `master` through an ordinary product pull request. Candidate preparation only verifies that the lockfile is tracked and unchanged; it never resolves dependencies or adds a lockfile change.

Fetch `origin/master`, record its commit, and create an isolated `release/pre-vX.Y.Z` worktree. Prepare the package version, reviewed Markdown release notes, and version-history entry as exactly one non-merge commit. The Markdown notes contain only user-visible `- ...` bullets. The matching history `<article>` carries `data-version="X.Y.Z"`, `data-release-notes-source="apps/macos/release-notes/vX.Y.Z.md"`, the same bullets as `<li>` elements, and a fixed-tag DMG URL.

```sh
MACOS_BRANCH="release/pre-v${MACOS_VERSION}"
MACOS_TAG="v${MACOS_VERSION}"
MACOS_WORKTREE_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-release.XXXXXX")"
MACOS_WORKTREE="$MACOS_WORKTREE_PARENT/worktree"
git fetch origin master --tags
MACOS_BASE_MASTER="$(git rev-parse origin/master)"
git worktree add -b "$MACOS_BRANCH" "$MACOS_WORKTREE" "$MACOS_BASE_MASTER"
cd "$MACOS_WORKTREE"
MACOS_NOTES="apps/macos/release-notes/${MACOS_TAG}.md"
git ls-files --error-unmatch apps/macos/Package.resolved
git diff --exit-code HEAD -- apps/macos/Package.resolved
mkdir -p apps/macos/release-notes
# Set apps/macos/package.json, write reviewed bullet notes, and add the matching
# article to website/landing/version-history.html.
test -s "$MACOS_NOTES"
node - "$MACOS_VERSION" "$MACOS_TAG" "$MACOS_NOTES" website/landing/version-history.html <<'NODE'
const { readFileSync } = require('node:fs')
const [version, tag, notesPath, historyPath] = process.argv.slice(2)
const notes = readFileSync(notesPath, 'utf8')
const history = readFileSync(historyPath, 'utf8')
const noteLines = notes.split(/\r?\n/).filter(line => line.length > 0)
if (noteLines.some(line => !/^- .+$/.test(line))) throw new Error('release notes may contain only bullets')
const bullets = noteLines.map(line => line.slice(2))
if (bullets.length === 0) throw new Error('release notes require user-visible bullets')
const escapedVersion = version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const article = new RegExp(`<article\\b[^>]*\\bdata-version="${escapedVersion}"[^>]*>([\\s\\S]*?)<\\/article>`).exec(history)?.[0]
if (!article) throw new Error('version-history article is missing')
if (!article.includes(`data-release-notes-source="${notesPath}"`)) throw new Error('release-note source mismatch')
if (!article.includes(`<h2>DS Harness ${version}</h2>`)) throw new Error('version-history heading mismatch')
const escapeHtml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;')
const listItems = [...article.matchAll(/<li>([\s\S]*?)<\/li>/g)].map(match => match[1].trim())
const expectedItems = bullets.map(escapeHtml)
if (JSON.stringify(listItems) !== JSON.stringify(expectedItems)) throw new Error('release-note bullets differ from version history')
const assetUrl = `https://github.com/GetSayAll/deepseek-harness-app/releases/download/${tag}/DS-Harness-${version}-arm64.dmg`
if (!article.includes(`href="${assetUrl}"`)) throw new Error('version-history DMG URL is not fixed to the tag')
NODE
git add apps/macos/package.json "$MACOS_NOTES" website/landing/version-history.html
MACOS_EXPECTED_CANDIDATE_PATHS="$(printf '%s\n' \
  apps/macos/package.json "$MACOS_NOTES" website/landing/version-history.html | LC_ALL=C sort)"
MACOS_ACTUAL_CANDIDATE_PATHS="$(git diff --cached --name-only | LC_ALL=C sort)"
test "$MACOS_ACTUAL_CANDIDATE_PATHS" = "$MACOS_EXPECTED_CANDIDATE_PATHS"
git commit -m "release(macos): prepare ${MACOS_TAG}"
```

The candidate branch is immutable after its first push. Never amend, rebase, force-push, or add a second commit. If review finds a required change, close the candidate, land the correction through `master`, and start a new candidate version.

Push the branch, open its pull request, and wait for review and required checks while leaving the pull request open and unmerged.

```sh
git push --set-upstream origin "$MACOS_BRANCH"
MACOS_PR_URL="$(gh pr create --base master --head "$MACOS_BRANCH" \
  --title "release(macos): prepare ${MACOS_TAG}" --body-file /absolute/path/pr-body.md)"
gh pr checks "$MACOS_BRANCH" --watch --fail-fast
test "$(gh pr view "$MACOS_BRANCH" --json reviewDecision --jq .reviewDecision)" = APPROVED
test "$(gh pr view "$MACOS_BRANCH" --json state --jq .state)" = OPEN
```

## B. Revalidate source before secrets or build

Before reading signing or Sparkle secrets and before running any build, re-fetch the base and remote candidate branch. The shell assertions below require a clean checkout, current `origin/master` as the sole parent, exactly one non-merge commit in `origin/master..HEAD`, a pushed branch equal to `HEAD`, the exact three allowed candidate paths, the committed package version, tracked and unchanged `Package.resolved`, and the same tracked non-empty notes file.

```sh
git fetch origin master "$MACOS_BRANCH" --tags
test -z "$(git status --porcelain)"
test "$(git rev-parse HEAD^)" = "$(git rev-parse origin/master)"
test "$(git rev-list --count origin/master..HEAD)" -eq 1
test "$(git show -s --format=%P HEAD | wc -w | tr -d ' ')" -eq 1
test "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$MACOS_BRANCH")"
MACOS_CANDIDATE_COMMIT="$(git rev-parse HEAD)"
test "$(git diff --name-only origin/master..HEAD | LC_ALL=C sort)" = "$MACOS_EXPECTED_CANDIDATE_PATHS"
MACOS_PACKAGE_VERSION="$(node -e "const fs=require('node:fs'); process.stdout.write(JSON.parse(fs.readFileSync('apps/macos/package.json','utf8')).version)")"
test "$MACOS_PACKAGE_VERSION" = "$MACOS_VERSION"
git ls-files --error-unmatch apps/macos/Package.resolved
git diff --exit-code HEAD -- apps/macos/Package.resolved
git ls-files --error-unmatch "$MACOS_NOTES"
test -s "$MACOS_NOTES"
test "$(gh pr view "$MACOS_BRANCH" --json state --jq .state)" = OPEN
! git merge-base --is-ancestor "$MACOS_CANDIDATE_COMMIT" origin/master
```

The candidate commit is the authority for shipped behavior. Dirty or uncommitted capability, including work in another checkout, must not be described in the notes or claimed as released.

## C. Build once with the same notes file

Use the tracked, non-empty `$MACOS_NOTES` for both `RELEASE_NOTES_FILE` and the later `gh release create --notes-file`. Do not regenerate or edit it after the candidate commit.

```sh
MACOS_SIGN_IDENTITY='Developer ID Application: ORGANIZATION (TEAMID)'
MACOS_NOTARY_PROFILE='dsh-notary'
MACOS_SPARKLE_PUBLIC_KEY='BASE64_PUBLIC_KEY'
MACOS_SPARKLE_PRIVATE_KEY_FILE='/restricted/path/sparkle-private-key'
test -s "$MACOS_NOTES"
test -s "$MACOS_SPARKLE_PRIVATE_KEY_FILE"
pnpm install --frozen-lockfile
test "$(uname -m)" = arm64
pnpm --filter @deepseek-ai/dsh-macos run test:host
pnpm --filter @deepseek-ai/dsh-macos run test:swift
APP_VERSION="$MACOS_VERSION" BUILD_NUMBER="$MACOS_BUILD" \
  SPARKLE_PUBLIC_ED_KEY="$MACOS_SPARKLE_PUBLIC_KEY" \
  pnpm --filter @deepseek-ai/dsh-macos run package:app
APP_VERSION="$MACOS_VERSION" BUILD_NUMBER="$MACOS_BUILD" RELEASE_TAG="$MACOS_TAG" \
  CODE_SIGN_IDENTITY="$MACOS_SIGN_IDENTITY" NOTARY_PROFILE="$MACOS_NOTARY_PROFILE" \
  SPARKLE_PUBLIC_ED_KEY="$MACOS_SPARKLE_PUBLIC_KEY" \
  SPARKLE_PRIVATE_KEY_FILE="$MACOS_SPARKLE_PRIVATE_KEY_FILE" \
  RELEASE_NOTES_FILE="$MACOS_NOTES" \
  pnpm --filter @deepseek-ai/dsh-macos run package:dmg:notarized
test -z "$(git status --porcelain)"
```

Require both shipped entry points to be single-architecture arm64 Mach-O files. These `lipo` and `file` assertions fail on absent, Intel, universal, or non-Mach-O files.

```sh
MACOS_APP_EXECUTABLE="apps/macos/dist/DS Harness.app/Contents/MacOS/DeepSeekHarness"
MACOS_NODE_EXECUTABLE="apps/macos/dist/DS Harness.app/Contents/Resources/runtime/node/bin/node"
for MACOS_EXECUTABLE in "$MACOS_APP_EXECUTABLE" "$MACOS_NODE_EXECUTABLE"; do
  test "$(lipo -archs "$MACOS_EXECUTABLE")" = arm64
  file "$MACOS_EXECUTABLE" | rg -q 'Mach-O.*arm64'
done
```

## D. Generate provenance and bind it to the tag

The candidate has four payloads: DMG, DMG SHA-256 file, Sparkle ZIP, and `appcast.xml`. Generate `candidate-provenance.json` with `branch`, `baseMasterCommit`, `tagCommit`, `version`, `build`, and each payload's byte size and SHA-256. The provenance file excludes its own digest; the annotated tag message records that digest.

```sh
MACOS_DMG_NAME="DS-Harness-${MACOS_VERSION}-arm64.dmg"
MACOS_CHECKSUM_NAME="${MACOS_DMG_NAME}.sha256"
MACOS_ZIP_NAME="DS-Harness-${MACOS_VERSION}-arm64.zip"
MACOS_APPCAST_NAME='appcast.xml'
MACOS_PROVENANCE_NAME='candidate-provenance.json'
MACOS_RELEASE_DIR='apps/macos/dist/release'
MACOS_DMG="$MACOS_RELEASE_DIR/$MACOS_DMG_NAME"
MACOS_CHECKSUM="$MACOS_RELEASE_DIR/$MACOS_CHECKSUM_NAME"
MACOS_UPDATE_ZIP="$MACOS_RELEASE_DIR/$MACOS_ZIP_NAME"
MACOS_APPCAST="$MACOS_RELEASE_DIR/$MACOS_APPCAST_NAME"
MACOS_PROVENANCE="$MACOS_RELEASE_DIR/$MACOS_PROVENANCE_NAME"
(cd "$MACOS_RELEASE_DIR" && shasum -a 256 -c "$MACOS_CHECKSUM_NAME")
node - "$MACOS_PROVENANCE" "$MACOS_BRANCH" "$MACOS_BASE_MASTER" \
  "$MACOS_CANDIDATE_COMMIT" "$MACOS_VERSION" "$MACOS_BUILD" \
  "$MACOS_DMG" "$MACOS_CHECKSUM" "$MACOS_UPDATE_ZIP" "$MACOS_APPCAST" <<'NODE'
const { createHash } = require('node:crypto')
const { readFileSync, statSync, writeFileSync } = require('node:fs')
const { basename } = require('node:path')
const [output, branch, baseMasterCommit, tagCommit, version, build, ...paths] = process.argv.slice(2)
if (!/^[1-9]\d*$/.test(build) || paths.length !== 4) throw new Error('invalid provenance input')
const payloads = Object.fromEntries(paths.map((path) => {
  const bytes = readFileSync(path)
  return [basename(path), {
    size: statSync(path).size,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  }]
}))
writeFileSync(output, `${JSON.stringify({
  schemaVersion: 1,
  branch,
  baseMasterCommit,
  tagCommit,
  version,
  build,
  payloads,
}, null, 2)}\n`)
NODE
test -s "$MACOS_PROVENANCE"
MACOS_PROVENANCE_SHA="$(shasum -a 256 "$MACOS_PROVENANCE" | awk '{print $1}')"
MACOS_TAG_MESSAGE="$(mktemp "${TMPDIR:-/tmp}/dsh-macos-tag-message.XXXXXX")"
printf 'DS Harness %s\ncandidate-provenance-sha256: %s\n' \
  "$MACOS_TAG" "$MACOS_PROVENANCE_SHA" >"$MACOS_TAG_MESSAGE"
git tag -a "$MACOS_TAG" "$MACOS_CANDIDATE_COMMIT" -F "$MACOS_TAG_MESSAGE"
git push origin "$MACOS_TAG"
git fetch origin master "$MACOS_BRANCH" --tags
test "$(git cat-file -t "$MACOS_TAG")" = tag
test "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$MACOS_BRANCH")"
test "$(git rev-parse HEAD)" = "$(git rev-parse "${MACOS_TAG}^{commit}")"
! git merge-base --is-ancestor "$(git rev-parse "${MACOS_TAG}^{commit}")" origin/master
test -z "$(git status --porcelain)"
```

The tag, remote branch, and `HEAD` now identify the same candidate commit. The pull request is still open; creating the pre-release while the tag commit is already an ancestor of `master` is forbidden.

## E. Publish exactly five assets and repeat full verification

Create one GitHub pre-release containing exactly the four payloads plus `candidate-provenance.json`. The same tracked notes file used by Sparkle is the GitHub body.

```sh
gh release create "$MACOS_TAG" \
  "$MACOS_DMG" "$MACOS_CHECKSUM" "$MACOS_UPDATE_ZIP" "$MACOS_APPCAST" "$MACOS_PROVENANCE" \
  --verify-tag --prerelease --title "DS Harness ${MACOS_TAG}" --notes-file "$MACOS_NOTES"
```

The operator repeats the following documented procedure after upload, immediately before stable promotion, and immediately after promotion. It checks the exact five names and count; verifies the provenance file's SHA-256 from the annotated tag; verifies all four payload sizes and hashes from the provenance record, thereby checking all five files; rechecks the DMG checksum; requires fixed-tag appcast enclosure and release-page URLs; and repeats Sparkle verification for both the ZIP enclosure signature and appcast signature.

```sh
MACOS_SIGN_UPDATE="apps/macos/.build/artifacts/sparkle/Sparkle/bin/sign_update"
MACOS_EXPECTED_ASSETS="$(printf '%s\n' \
  "$MACOS_DMG_NAME" "$MACOS_CHECKSUM_NAME" "$MACOS_ZIP_NAME" \
  "$MACOS_APPCAST_NAME" "$MACOS_PROVENANCE_NAME" | LC_ALL=C sort)"

verify_downloaded_candidate() {
  local directory="$1"
  local actual_names provenance_sha enclosure_signature
  actual_names="$(find "$directory" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)"
  test "$actual_names" = "$MACOS_EXPECTED_ASSETS"
  provenance_sha="$(git tag -l "$MACOS_TAG" --format='%(contents)' \
    | sed -n 's/^candidate-provenance-sha256: \([0-9a-f]\{64\}\)$/\1/p')"
  test -n "$provenance_sha"
  test "$provenance_sha" = "$(shasum -a 256 "$directory/$MACOS_PROVENANCE_NAME" | awk '{print $1}')"
  node - "$directory" "$MACOS_BRANCH" "$(git rev-parse "${MACOS_TAG}^{commit}^")" \
    "$(git rev-parse "${MACOS_TAG}^{commit}")" "$MACOS_VERSION" "$MACOS_BUILD" \
    "$MACOS_DMG_NAME" "$MACOS_CHECKSUM_NAME" "$MACOS_ZIP_NAME" "$MACOS_APPCAST_NAME" <<'NODE'
const { createHash } = require('node:crypto')
const { readFileSync, statSync } = require('node:fs')
const { join } = require('node:path')
const [directory, branch, baseMasterCommit, tagCommit, version, build, ...names] = process.argv.slice(2)
const record = JSON.parse(readFileSync(join(directory, 'candidate-provenance.json'), 'utf8'))
for (const [field, expected] of Object.entries({ branch, baseMasterCommit, tagCommit, version, build })) {
  if (record[field] !== expected) throw new Error(`provenance ${field} mismatch`)
}
if (record.schemaVersion !== 1 || Object.keys(record.payloads).sort().join('\n') !== names.sort().join('\n')) {
  throw new Error('provenance payload set mismatch')
}
for (const name of names) {
  const path = join(directory, name)
  const bytes = readFileSync(path)
  const expected = record.payloads[name]
  if (statSync(path).size !== expected.size || createHash('sha256').update(bytes).digest('hex') !== expected.sha256) {
    throw new Error(`payload digest mismatch: ${name}`)
  }
}
NODE
  (cd "$directory" && shasum -a 256 -c "$MACOS_CHECKSUM_NAME")
  rg -Fq "url=\"https://github.com/GetSayAll/deepseek-harness-app/releases/download/$MACOS_TAG/$MACOS_ZIP_NAME\"" \
    "$directory/$MACOS_APPCAST_NAME"
  rg -Fq "https://github.com/GetSayAll/deepseek-harness-app/releases/tag/$MACOS_TAG" \
    "$directory/$MACOS_APPCAST_NAME"
  enclosure_signature="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' \
    "$directory/$MACOS_APPCAST_NAME" | head -n 1)"
  test -n "$enclosure_signature"
  "$MACOS_SIGN_UPDATE" --verify --ed-key-file "$MACOS_SPARKLE_PRIVATE_KEY_FILE" \
    "$directory/$MACOS_ZIP_NAME" "$enclosure_signature"
  "$MACOS_SIGN_UPDATE" --verify --ed-key-file "$MACOS_SPARKLE_PRIVATE_KEY_FILE" \
    "$directory/$MACOS_APPCAST_NAME"
}

download_and_verify_candidate() {
  local stage="$1"
  local directory remote_names
  directory="$(mktemp -d "${TMPDIR:-/tmp}/dsh-macos-${stage}.XXXXXX")"
  remote_names="$(gh release view "$MACOS_TAG" --json assets --jq '.assets[].name' | LC_ALL=C sort)"
  test "$remote_names" = "$MACOS_EXPECTED_ASSETS"
  gh release download "$MACOS_TAG" --dir "$directory"
  verify_downloaded_candidate "$directory"
}

test "$(gh release view "$MACOS_TAG" --json isDraft --jq .isDraft)" = false
test "$(gh release view "$MACOS_TAG" --json isPrerelease --jq .isPrerelease)" = true
download_and_verify_candidate candidate-upload
```

Stable clients use `releases/latest/download/appcast.xml`; preview-enabled clients select the newest non-draft Release carrying `appcast.xml`. The fixed-tag enclosure URL keeps the appcast bound to the ZIP from the same candidate.

## F. Record the exact candidate commit on `master`

After public candidate verification, merge the already-reviewed pull request only by merge commit or true fast-forward. Squash merge and rebase merge are forbidden because they replace the tagged candidate commit. Candidate-branch rebase and force-push remain forbidden.

```sh
# Merge the existing pull request using a strategy that preserves $MACOS_CANDIDATE_COMMIT.
git fetch origin master --tags
test "$(git rev-parse "${MACOS_TAG}^{commit}")" = "$MACOS_CANDIDATE_COMMIT"
git merge-base --is-ancestor "$MACOS_CANDIDATE_COMMIT" origin/master
```

If the ancestry assertion fails, the candidate is not recorded on `master` and cannot become stable.

## G. Promote metadata only

Stable promotion requires an explicit exact tag. Re-fetch the source refs, require the unchanged tag commit to remain an ancestor of `origin/master`, repeat the complete public verification procedure, change only GitHub Release metadata, then repeat the same procedure again.

```sh
git fetch origin master --tags
test "$(git rev-parse "${MACOS_TAG}^{commit}")" = "$MACOS_CANDIDATE_COMMIT"
git merge-base --is-ancestor "$MACOS_CANDIDATE_COMMIT" origin/master
test "$(gh release view "$MACOS_TAG" --json isPrerelease --jq .isPrerelease)" = true
download_and_verify_candidate promote-before
gh release edit "$MACOS_TAG" --prerelease=false --latest
test "$(gh release view "$MACOS_TAG" --json isPrerelease --jq .isPrerelease)" = false
download_and_verify_candidate promote-after
```

Promotion never rebuilds, re-signs, re-notarizes, renames, deletes, uploads, or replaces an asset. The stable release is the same tag and the same five files as the publicly verified candidate.

## Failed candidates and credentials

A failed public candidate remains a pre-release with its original tag and assets. Do not replace its bytes, move or recreate its tag, reuse its version, or promote it. Fixes return through `master`, and a later attempt uses a new exact version.

Keep Developer ID private keys, notary credentials, and the Sparkle private Ed25519 key outside the repository and command logs. The public Ed25519 key is safe to embed. Never commit or print private key material, passwords, API key files, or Keychain secrets.
