#!/bin/sh
# Builds the distributable artifacts — dist/NotchHub.dmg and dist/NotchHub.zip —
# from one fresh release app bundle.
# Idempotent — safe to re-run.
#
# Both come out of the SAME build, and every previous .dmg/.zip in dist/ is
# removed first. Building them separately is how dist/ ended up holding a disk
# image and an archive from different days, either of which could have been
# shipped by mistake.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="NotchHub"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME.dmg"
ZIP="$DIST/$APP_NAME.zip"
STAGE="$DIST/.dmg-stage"

# Always build the app the artifacts are made from, rather than trusting
# whatever happens to be in dist/ — an archive wrapped around a stale bundle is
# the mistake this script exists to prevent.
echo "==> building the app bundle"
"$ROOT/scripts/build_app.sh" >/dev/null
[ -d "$APP" ] || { echo "error: $APP was not produced" >&2; exit 1; }

echo "==> removing old artifacts"
find "$DIST" -maxdepth 1 \( -name '*.dmg' -o -name '*.zip' \) -print -delete

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo dev)"

# --- Disk image -------------------------------------------------------------
# The staging folder is what the user sees when the image is mounted: the app,
# and an /Applications alias to drag it into.
echo "==> staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> hdiutil create ($APP_NAME $VERSION)"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

# --- Archive ----------------------------------------------------------------
# `ditto`, not `zip`: it is the only one that carries symlinks, resource forks
# and the code signature through intact. A plain `zip` scatters AppleDouble
# "._" files through the bundle and can leave the signature unverifiable on the
# other side — which is exactly what the previous hand-made archive did.
echo "==> ditto archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> done"
for file in "$DMG" "$ZIP"; do
  ls -lh "$file" | awk '{ print "    " $5, $9 }'
  shasum -a 256 "$file" | awk '{ print "      sha256 " $1 }'
done
