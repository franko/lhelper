#!/bin/sh
# Install lhelper: compile the executable and copy the runtime files.
# Usage: sh install.sh <prefix>
# The prefix should contain a "bin" directory present in your PATH.
set -e

if [ "$#" != 1 ]; then
    echo "Usage: $0 <prefix>"
    exit 1
fi

PREFIX="$1"
if [ -z "${DESTDIR+x}" ]; then
    DESTDIR="$PREFIX"
fi

LHELPER_PACKAGE_VERSION=2

sh build.sh

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) EXE_SUFFIX=".exe" ;;
*) EXE_SUFFIX="" ;;
esac

echo "Installing lhelper with prefix $DESTDIR"

mkdir -p "$DESTDIR/bin"
mkdir -p "$DESTDIR/share/lhelper/lua"
mkdir -p "$DESTDIR/share/lhelper/recipes"
mkdir -p "$DESTDIR/share/lhelper/patch"
mkdir -p "$DESTDIR/var/lhelper/archives"
mkdir -p "$DESTDIR/var/lhelper/packages/$LHELPER_PACKAGE_VERSION"
mkdir -p "$DESTDIR/var/lhelper/digests"

cp "build/lhelper$EXE_SUFFIX" "$DESTDIR/bin"
cp lua/*.lua "$DESTDIR/share/lhelper/lua"
cp recipes/index recipes/*.lua "$DESTDIR/share/lhelper/recipes"
cp patch/*.patch "$DESTDIR/share/lhelper/patch"
cp lhelper-bash-init "$DESTDIR/share/lhelper"

echo "lhelper installed in $DESTDIR/bin"
