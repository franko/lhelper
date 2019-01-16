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
mkdir -p "$DESTDIR/var/lib/lhelper"

cp lhelper-env "$DESTDIR/bin"
cp env.sh "$DESTDIR/share/lhelper"
cp build-helper.sh "$DESTDIR/share/lhelper"
cp recipes/*.sh "$DESTDIR/share/lhelper/recipes"
cp patch/*.patch "$DESTDIR/share/lhelper/patch"

cat << EOF > "$DESTDIR/bin/lhelper"
#!/usr/bin/env bash

LHELPER_PREFIX="$PREFIX"

if [ "\$#" -lt 1 ]; then
    echo "Usage: \$0 <recipe-name>"
    exit 1
fi

if [ -z \${LHELPER_ENV_NAME+x} ]; then
    echo "error: no environment defined"
    exit 1
fi

INSTALL_PREFIX="\$CMAKE_PREFIX_PATH"
RECIPE="\$1"

export LHELPER_WORKING_DIR="\$LHELPER_PREFIX/var/lib/lhelper"
export LHELPER_DIR="\$LHELPER_PREFIX/share/lhelper"

mkdir -p "\$LHELPER_WORKING_DIR/builds"
mkdir -p "\$LHELPER_WORKING_DIR/repos"
mkdir -p "\$LHELPER_WORKING_DIR/archives"

source "\$LHELPER_DIR/env.sh"
exec bash "\$LHELPER_DIR/recipes/\$RECIPE.sh"
EOF

chmod a+x "$DESTDIR/bin/lhelper"
chmod a+x "$DESTDIR/bin/lhelper-env"

echo "done"
