#!/bin/bash
# Builds a signed and notarized release of K5K1 Prog into dist/:
#
#   dist/K5K1-Prog-<version>.zip   the app, stapled (also the in-app update archive)
#   dist/K5K1-Prog-<version>.dmg   the app + an Applications link, signed and stapled
#   dist/appcast.xml               Sparkle feed for in-app updates (EdDSA-signed zip)
#   dist/SHA256SUMS.txt
#   dist/RELEASE_NOTES.md          release-notes/<version>.md + checksums, for `gh release create`
#
# Needs (once):
#   - a "Developer ID Application" certificate in the login keychain;
#   - a notarytool keychain profile:
#       xcrun notarytool store-credentials k5k1prog --apple-id <Apple ID> --team-id <team id>
#     (asks for an app-specific password from account.apple.com)
#   - a Sparkle EdDSA key in the login keychain, its public key in Resources/SparklePublicKey.txt:
#       .build/artifacts/sparkle/Sparkle/bin/generate_keys      (after `swift package resolve`)
#
# Per release: bump K5.version in Sources/K5Core/Constants.swift and write release-notes/<version>.md.
#
# Settings (environment):
#   SIGN_IDENTITY   code signing identity (default: the first "Developer ID Application" one)
#   NOTARY_PROFILE  notarytool keychain profile (default: k5k1prog)
#   NOTARIZE=0      sign only, skip notarization (local test; Gatekeeper will block the result)
#   SKIP_TESTS=1    skip `swift test`
#   ALLOW_DIRTY=1   allow uncommitted changes
#   Local update tests only: SPARKLE_KEY_FILE (private key file instead of the keychain) together with
#   SPARKLE_PUBLIC_KEY, and DOWNLOAD_URL_PREFIX (where the zip is served instead of GitHub).
#
# The appcast is attached to every release; the app reads
# https://github.com/ERuban/k5k1prog-mac/releases/latest/download/appcast.xml, so publishing the
# release is what makes installed copies offer the update.
#
# The script does not publish anything. It prints the `gh release create` command at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="https://github.com/ERuban/k5k1prog-mac"
NOTARY_PROFILE="${NOTARY_PROFILE:-k5k1prog}"
NOTARIZE="${NOTARIZE:-1}"
APP="K5K1 Prog.app"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/K5Core/Constants.swift)"
NAME="K5K1-Prog-$VERSION"
DIST="dist"
NOTES="release-notes/$VERSION.md"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-$REPO_URL/releases/download/v$VERSION}"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------------------
[ -n "$VERSION" ] || die "K5.version not found in Sources/K5Core/Constants.swift"
[ -s "$NOTES" ] || die "release notes $NOTES missing"

if [ "${ALLOW_DIRTY:-0}" != 1 ]; then
    [ -z "$(git status --porcelain 2>/dev/null)" ] || die "uncommitted changes (commit first, or ALLOW_DIRTY=1)"
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
fi
[ -n "$SIGN_IDENTITY" ] || die "no \"Developer ID Application\" certificate found (or set SIGN_IDENTITY)"

if [ "$NOTARIZE" = 1 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || die "notarytool profile '$NOTARY_PROFILE' not usable; create it with:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <team id>"
fi

# Sparkle: the key that signs the update must be the one the app trusts, or every installed
# copy rejects the update.
[ -x "$SPARKLE_BIN/sign_update" ] || swift package resolve >/dev/null
[ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle tools not found in $SPARKLE_BIN"
APP_KEY="${SPARKLE_PUBLIC_KEY:-$( { grep -v '^#' Resources/SparklePublicKey.txt 2>/dev/null || true; } | tr -d '[:space:]')}"
[ -n "$APP_KEY" ] || die "no Sparkle public key in Resources/SparklePublicKey.txt (run $SPARKLE_BIN/generate_keys)"
if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
    sign_update() { "$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$@"; }
else
    KEYCHAIN_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null | tr -d '[:space:]')" \
        || die "no Sparkle key in the keychain (run $SPARKLE_BIN/generate_keys)"
    [ "$KEYCHAIN_KEY" = "$APP_KEY" ] \
        || die "Sparkle key in the keychain ($KEYCHAIN_KEY) differs from Resources/SparklePublicKey.txt ($APP_KEY)"
    sign_update() { "$SPARKLE_BIN/sign_update" "$@"; }
fi

echo "version:  $VERSION"
echo "identity: $SIGN_IDENTITY"
echo "notarize: $([ "$NOTARIZE" = 1 ] && echo "yes (profile $NOTARY_PROFILE)" || echo no)"
echo "sparkle:  $APP_KEY"

notarize() {   # <file>: submit, wait, fail on anything but Accepted
    local out id
    out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || true
    echo "$out"
    if ! grep -q 'status: Accepted' <<<"$out"; then
        id="$(sed -n 's/^ *id: \(.*\)/\1/p' <<<"$out" | head -1)"
        [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" || true
        die "notarization of $1 failed"
    fi
}

# --- test + build ----------------------------------------------------------------------
if [ "${SKIP_TESTS:-0}" != 1 ]; then
    step "swift test"
    swift test
fi

step "build"
SPARKLE_PUBLIC_KEY="$APP_KEY" ./scripts/build_app.sh
[ "$(lipo -archs "$APP/Contents/MacOS/K5K1Prog")" = "x86_64 arm64" ] || die "not a universal binary"
[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" = "$APP_KEY" ] \
    || die "SUPublicEDKey in the app differs from the signing key"

rm -rf "$DIST"
mkdir -p "$DIST"

# --- app: sign (inside out), notarize, staple -------------------------------------------
step "sign app"
sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$NOTARIZE" = 1 ]; then
    step "notarize app"
    ditto -c -k --keepParent "$APP" "$DIST/notarize-app.zip"
    notarize "$DIST/notarize-app.zip"
    rm "$DIST/notarize-app.zip"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

step "zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

# --- dmg: app + Applications link, sign, notarize, staple ------------------------------
step "dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "K5K1 Prog $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
    -ov "$DIST/$NAME.dmg"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$NAME.dmg"

if [ "$NOTARIZE" = 1 ]; then
    step "notarize dmg"
    notarize "$DIST/$NAME.dmg"
    xcrun stapler staple "$DIST/$NAME.dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DIST/$NAME.dmg"
fi

# --- appcast (Sparkle feed) --------------------------------------------------------------
step "appcast"
SIGNATURE="$(sign_update -p "$DIST/$NAME.zip")"
[ -n "$SIGNATURE" ] || die "sign_update produced no signature"
ZIP_URL="$DOWNLOAD_URL_PREFIX/$NAME.zip"
ZIP_LENGTH="$(stat -f %z "$DIST/$NAME.zip")"
VERSION="$VERSION" NOTES="$NOTES" SIGNATURE="$SIGNATURE" REPO_URL="$REPO_URL" URL="$ZIP_URL" LENGTH="$ZIP_LENGTH" \
python3 - > "$DIST/appcast.xml" <<'PY'
import email.utils, os, xml.sax.saxutils as x
e = os.environ
notes = open(e["NOTES"], encoding="utf-8").read().strip().replace("]]>", "]]]]><![CDATA[>")
q = lambda s: x.quoteattr(s)
print(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>K5K1 Prog</title>
    <link>{x.escape(e["REPO_URL"])}</link>
    <language>en</language>
    <item>
      <title>Version {x.escape(e["VERSION"])}</title>
      <link>{x.escape(e["REPO_URL"])}/releases/tag/v{x.escape(e["VERSION"])}</link>
      <sparkle:version>{x.escape(e["VERSION"])}</sparkle:version>
      <sparkle:shortVersionString>{x.escape(e["VERSION"])}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.0.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{x.escape(e["REPO_URL"])}/releases</sparkle:fullReleaseNotesLink>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <description sparkle:format="markdown"><![CDATA[{notes}]]></description>
      <enclosure url={q(e["URL"])} length={q(e["LENGTH"])} type="application/octet-stream"
                 sparkle:edSignature={q(e["SIGNATURE"])}/>
    </item>
  </channel>
</rss>''')
PY
xmllint --noout "$DIST/appcast.xml"
sign_update --verify "$DIST/$NAME.zip" "$SIGNATURE" >/dev/null 2>&1 || [ -n "${SPARKLE_KEY_FILE:-}" ] \
    || die "the zip signature does not verify"

# --- checksums + notes ------------------------------------------------------------------
step "checksums"
(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)
{ cat "$NOTES"; printf '\n### Checksums (SHA-256)\n```\n'; cat "$DIST/SHA256SUMS.txt"; printf '```\n'; } \
    > "$DIST/RELEASE_NOTES.md"

step "done"
ls -l "$DIST"
if [ "$NOTARIZE" != 1 ]; then
    echo
    echo "NOT notarized: for local testing only, do not publish these files."
    exit 0
fi
cat <<EOF

Publish (after the commit is pushed):
  git tag v$VERSION && git push origin v$VERSION
  gh release create v$VERSION $DIST/$NAME.dmg $DIST/$NAME.zip $DIST/appcast.xml $DIST/SHA256SUMS.txt \\
      --title "K5K1 Prog $VERSION" --notes-file $DIST/RELEASE_NOTES.md
EOF
