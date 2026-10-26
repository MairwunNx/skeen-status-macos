#!/usr/bin/env bash
# Builds Skeen Status from source and installs it into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/MairwunNx/skeen-status-macos/master/scripts/install.sh | bash
#
# Run it from a checkout to build that checkout instead of a fresh clone.
# Environment:
#   SKEEN_SIGN_IDENTITY  code-signing identity; "-" (ad hoc) by default.
#                        A stable identity, even a self-signed one, keeps
#                        Keychain from asking for the password again after
#                        each update.
#   SKEEN_REF            branch or tag to build; master by default.
#   SKEEN_DEST           install folder; /Applications by default.

set -euo pipefail

REPO="https://github.com/MairwunNx/skeen-status-macos.git"
REF="${SKEEN_REF:-master}"
IDENTITY="${SKEEN_SIGN_IDENTITY:--}"
DEST="${SKEEN_DEST:-/Applications}"
APP="SkeenStatus.app"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "Skeen Status runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 26 )) || die "Skeen Status needs macOS 26 or newer, this Mac runs $(sw_vers -productVersion)."

# Xcode, not just the Command Line Tools, builds the app.
if ! xcodebuild -version >/dev/null 2>&1; then
    if [[ -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        die "Install Xcode from the App Store first: https://apps.apple.com/app/xcode/id497799835"
    fi
fi
say "Using $(xcodebuild -version | head -1)"

# The status orb is a Metal shader, and newer Xcode ships its compiler apart.
if ! xcrun -f metal >/dev/null 2>&1 || ! xcrun metal --version >/dev/null 2>&1; then
    say "Downloading the Metal toolchain (about 800 MB, once)"
    xcodebuild -downloadComponent MetalToolchain
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n "$script_dir" && -f "$script_dir/../SkeenStatus.xcodeproj/project.pbxproj" ]]; then
    src="$(cd "$script_dir/.." && pwd)"
    say "Building the checkout in $src"
else
    say "Cloning $REPO ($REF)"
    git clone --quiet --depth 1 --branch "$REF" "$REPO" "$work/src"
    src="$work/src"
fi

say "Building (this takes a few minutes the first time)"
xcodebuild \
    -project "$src/SkeenStatus.xcodeproj" \
    -scheme SkeenStatus \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$work/build" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build >"$work/build.log" 2>&1 || {
        tail -40 "$work/build.log" >&2
        die "The build failed; the full log is above."
    }

built="$work/build/Build/Products/Release/$APP"
[[ -d "$built" ]] || die "The build finished without $APP."

if pgrep -x SkeenStatus >/dev/null; then
    say "Quitting the running Skeen Status"
    osascript -e 'tell application id "com.mairwunnx.SkeenStatus" to quit' >/dev/null 2>&1 || pkill -x SkeenStatus || true
    sleep 1
fi

if [[ ! -w "$DEST" ]]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi
say "Installing into $DEST"
rm -rf "${DEST:?}/$APP"
ditto "$built" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

say "Starting Skeen Status: look for the dot in the menu bar"
open "$DEST/$APP"
