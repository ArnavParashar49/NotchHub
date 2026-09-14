#!/bin/sh
# Runs the unit tests (NotchHubCoreTests + NotchHubSystemTests).
#
# With only the Command Line Tools installed (no Xcode), swift-testing ships
# inside the CLT but is not on SwiftPM's search paths. A bare `swift test` then
# either fails with "no such module 'Testing'" or — if the paths come from the
# manifest instead — builds and exits 0 having run NOTHING. SwiftPM only detects
# and runs swift-testing when the paths are passed on the command line, so pass
# them here whenever the active developer directory is the CLT.
set -eu

cd "$(dirname "$0")/.."

DEVELOPER_DIR_ACTIVE="$(xcode-select -p 2>/dev/null || true)"
CLT_DEV=/Library/Developer/CommandLineTools/Library/Developer

if [ "$DEVELOPER_DIR_ACTIVE" = "/Library/Developer/CommandLineTools" ] \
  && [ -d "$CLT_DEV/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$CLT_DEV/Frameworks" \
    -Xlinker -F -Xlinker "$CLT_DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT_DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT_DEV/usr/lib" \
    "$@"
fi

exec swift test "$@"
