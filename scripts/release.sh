#!/bin/bash
# Builds a signed and notarized release of K5K1 Prog into dist/:
#
#   dist/K5K1-Prog-<version>.zip   the app, stapled
#   dist/K5K1-Prog-<version>.dmg   the app + an Applications link, signed and stapled
#   dist/SHA256SUMS.txt
#
# Needs (once):
#   - a "Developer ID Application" certificate in the login keychain;
#   - a notarytool keychain profile:
#       xcrun notarytool store-credentials k5k1prog --apple-id <Apple ID> --team-id <team id>
#     (asks for an app-specific password from account.apple.com)
#
# Settings (environment):
#   SIGN_IDENTITY   code signing identity (default: the first "Developer ID Application" one)
#   NOTARY_PROFILE  notarytool keychain profile (default: k5k1prog)
#   NOTARIZE=0      sign only, skip notarization (local test; Gatekeeper will block the result)
#   SKIP_TESTS=1    skip `swift test`
#   ALLOW_DIRTY=1   allow uncommitted changes
#
# The script does not publish anything. It prints the `gh release create` command at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-k5k1prog}"
NOTARIZE="${NOTARIZE:-1}"
APP="K5K1 Prog.app"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/K5Core/Constants.swift)"
NAME="K5K1-Prog-$VERSION"
DIST="dist"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------------------
[ -n "$VERSION" ] || die "K5.version not found in Sources/K5Core/Constants.swift"

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

echo "version:  $VERSION"
echo "identity: $SIGN_IDENTITY"
echo "notarize: $([ "$NOTARIZE" = 1 ] && echo "yes (profile $NOTARY_PROFILE)" || echo no)"

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
./scripts/build_app.sh
[ "$(lipo -archs "$APP/Contents/MacOS/K5K1Prog")" = "x86_64 arm64" ] || die "not a universal binary"

rm -rf "$DIST"
mkdir -p "$DIST"

# --- app: sign, notarize, staple -------------------------------------------------------
step "sign app"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "$NOTARIZE" = 1 ]; then
    step "notarize app"
    ditto -c -k --keepParent "$APP" "$DIST/notarize-app.zip"
    notarize "$DIST/notarize-app.zip"
    rm "$DIST/notarize-app.zip"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

step "zip"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"

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

# --- checksums -------------------------------------------------------------------------
step "checksums"
(cd "$DIST" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)

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
  gh release create v$VERSION $DIST/$NAME.dmg $DIST/$NAME.zip $DIST/SHA256SUMS.txt \\
      --title "K5K1 Prog $VERSION" --notes-file <release notes>
EOF
