#!/usr/bin/env bash

if [ $# != "1" ]; then
    echo "Usage: $0 <prefix>"
    exit 1
fi

PREFIX="$1"

if [ -z "${DESTDIR+x}" ]; then
    DESTDIR="$PREFIX"
fi

echo "Installing lhelper with prefix $DESTDIR"

mkdir -p "$DESTDIR/bin"
mkdir -p "$DESTDIR/share/lhelper/recipes"
mkdir -p "$DESTDIR/share/lhelper/patch"
mkdir -p "$DESTDIR/var/lib/lhelper/builds"
mkdir -p "$DESTDIR/var/lib/lhelper/repos"
mkdir -p "$DESTDIR/var/lib/lhelper/archives"
mkdir -p "$DESTDIR/var/lib/lhelper/packages"
mkdir -p "$DESTDIR/var/lib/lhelper/environments"
mkdir -p "$DESTDIR/var/lib/lhelper/env"
mkdir -p "$DESTDIR/var/lib/lhelper/digests"

cp lhelper-config-default "$DESTDIR/share/lhelper"
cp build-helper.sh "$DESTDIR/share/lhelper"
cp create-env.sh "$DESTDIR/share/lhelper"
cp recipes/*.sh "$DESTDIR/share/lhelper/recipes"
cp patch/*.patch "$DESTDIR/share/lhelper/patch"
cp lhelper "$DESTDIR/bin"

chmod a+x "$DESTDIR/bin/lhelper"

echo "done"
