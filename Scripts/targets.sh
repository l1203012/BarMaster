# shellcheck shell=bash
# Module graph used by build.sh. Keep in sync with Package.swift.
# LIBS and EXES are read by the scripts that source this file.
# shellcheck disable=SC2034
LIBS=""
# shellcheck disable=SC2034
EXES="BarMasterApp"

deps() {
    case $1 in
        BarMasterApp) echo "" ;;
        *) echo "unknown target: $1" >&2; exit 1 ;;
    esac
}
