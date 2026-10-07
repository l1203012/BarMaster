#!/bin/bash
# Builds BarMaster with plain swiftc, so it works with only the Command Line
# Tools installed (same approach as Whiteprint).
#
#   Scripts/build.sh              build every module and the executable
#   Scripts/build.sh app          build .build/BarMaster.app
#   Scripts/build.sh run          build the app, quit any running copy, open it
#   Scripts/build.sh install      optimised build into /Applications, then open it
#
#   CONFIG=release   optimised build (default: debug)
#   ARCHS="arm64 x86_64"   architectures (default: this Mac; release: both)
#   SIGN_IDENTITY=…   default: "BarMaster Dev" when Scripts/make-dev-cert.sh has
#                     created it, else ad-hoc "-". Ad-hoc builds get a new identity
#                     every time, so macOS asks for Accessibility/Automation again.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG=${CONFIG:-debug}
if [ "$CONFIG" = release ]; then
    ARCHS=${ARCHS:-"arm64 x86_64"}
    OPT="-O -whole-module-optimization"
else
    ARCHS=${ARCHS:-$(uname -m)}
    OPT="-Onone -g"
fi
OUT=$ROOT/.build/clt/$CONFIG
MIN_MACOS=13.0
APP=$ROOT/.build/BarMaster.app
# shellcheck source=Scripts/targets.sh
source "$ROOT/Scripts/targets.sh"

sources() { find "$ROOT/Sources/$1" -name '*.swift' | sort; }

# Rebuild only when a source or dependency is newer than the output.
up_to_date() {
    local output=$1 target=$2
    [ -e "$output" ] || return 1
    [ -z "$(find "$ROOT/Sources/$target" -name '*.swift' -newer "$output" | head -1)" ] || return 1
    local dep
    for dep in $(deps "$target"); do
        [ "$OUT/$ARCH/lib$dep.a" -nt "$output" ] && return 1
    done
    return 0
}

build_lib() {
    local target=$1 dir=$OUT/$ARCH dep
    for dep in $(deps "$target"); do build_lib "$dep"; done
    up_to_date "$dir/lib$target.a" "$target" && return 0
    echo "• $target ($ARCH)"
    mkdir -p "$dir"
    # shellcheck disable=SC2046,SC2086
    swiftc -parse-as-library -module-name "$target" $OPT \
        -target "$ARCH-apple-macos$MIN_MACOS" -I "$dir" \
        -emit-module -emit-module-path "$dir/$target.swiftmodule" \
        -emit-library -static -o "$dir/lib$target.a" \
        $(sources "$target")
}

build_exe() {
    local target=$1 dir=$OUT/$ARCH dep links="" parse=""
    for dep in $(deps "$target"); do
        build_lib "$dep"
        links="$links -l$dep"
    done
    up_to_date "$dir/$target" "$target" && return 0
    echo "• $target ($ARCH)"
    mkdir -p "$dir"
    # A target with main.swift uses top-level code; otherwise it has an @main type.
    [ -e "$ROOT/Sources/$target/main.swift" ] || parse="-parse-as-library"
    # shellcheck disable=SC2046,SC2086
    swiftc $parse -module-name "$target" $OPT \
        -target "$ARCH-apple-macos$MIN_MACOS" -I "$dir" -L "$dir" $links \
        -o "$dir/$target" $(sources "$target")
}

build() {
    local target
    for ARCH in $ARCHS; do
        for target in "$@"; do
            case " $EXES " in
                *" $target "*) build_exe "$target" ;;
                *) build_lib "$target" ;;
            esac
        done
    done
}

# Merges the per-architecture builds of an executable into one binary.
universal() {
    local target=$1 dest=$2 inputs="" arch
    for arch in $ARCHS; do inputs="$inputs $OUT/$arch/$target"; done
    # shellcheck disable=SC2086
    lipo -create $inputs -output "$dest"
}

bundle() {
    # shellcheck disable=SC2086 # EXES is a space-separated list
    build $EXES
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
    if [ -d "$ROOT/Resources/App" ]; then
        cp -R "$ROOT/Resources/App/." "$APP/Contents/Resources/"
    fi
    universal BarMasterApp "$APP/Contents/MacOS/BarMaster"
    local build_number
    build_number=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)
    plutil -replace CFBundleVersion -string "$build_number" "$APP/Contents/Info.plist"
    local identity=${SIGN_IDENTITY:-}
    if [ -z "$identity" ]; then
        identity=-
        security find-identity -v -p codesigning | grep -q '"BarMaster Dev"' && identity="BarMaster Dev"
    fi
    [ "$identity" = - ] && echo "! ad-hoc signed: permissions reset on every build (run Scripts/make-dev-cert.sh once)"
    codesign --force --sign "$identity" "$APP"
    echo "✓ $APP"
}

# shellcheck disable=SC2086 # LIBS and EXES are space-separated lists
case "${1:-all}" in
    all) build $LIBS $EXES ;;
    app) bundle ;;
    run)
        bundle
        pkill -x BarMaster 2>/dev/null || true
        open "$APP"
        ;;
    install)
        CONFIG=release ARCHS=$(uname -m) "$0" app
        pkill -x BarMaster 2>/dev/null || true
        rm -rf /Applications/BarMaster.app
        ditto "$APP" /Applications/BarMaster.app
        open /Applications/BarMaster.app
        echo "✓ installed /Applications/BarMaster.app"
        ;;
    *) build "$@" ;;
esac
