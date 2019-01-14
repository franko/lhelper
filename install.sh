#!/usr/bin/env bash

if [ $# != "1" ]; then
    echo "Usage: $0 <prefix>"
    exit 1
fi

PREFIX="$1"

if [ -z "${DESTDIR+x}" ]; then
    DESTDIR="$PREFIX"
fi

echo "Installing cook with prefix $DESTDIR"

mkdir -p "$DESTDIR/bin"
mkdir -p "$DESTDIR/share/cook/recipes"
mkdir -p "$DESTDIR/share/cook/patch"
mkdir -p "$DESTDIR/var/lib/cook"

cp cook-env "$DESTDIR/bin"
cp env.sh "$DESTDIR/share/cook"
cp build-helper.sh "$DESTDIR/share/cook"
cp recipes/*.sh "$DESTDIR/share/cook/recipes"
cp patch/*.patch "$DESTDIR/share/cook/patch"

cat << EOF > "$DESTDIR/bin/cook"
#!/usr/bin/env bash

COOK_PREFIX="$PREFIX"

if [ "\$#" -lt 1 ]; then
    echo "Usage: \$0 <recipe-name>"
    exit 1
fi

if [ -z \${COOK_ENV_NAME+x} ]; then
    echo "error: no environment defined"
    exit 1
fi

INSTALL_PREFIX="\$CMAKE_PREFIX_PATH"
RECIPE="\$1"

export COOK_WORKING_DIR="\$COOK_PREFIX/var/lib/cook"
export COOK_DIR="\$COOK_PREFIX/share/cook"

mkdir -p "\$COOK_WORKING_DIR/builds"
mkdir -p "\$COOK_WORKING_DIR/repos"
mkdir -p "\$COOK_WORKING_DIR/archives"

source "\$COOK_DIR/env.sh"
exec bash "\$COOK_DIR/recipes/\$RECIPE.sh"
EOF

chmod a+x "$DESTDIR/bin/cook"
chmod a+x "$DESTDIR/bin/cook-env"

echo "done"
