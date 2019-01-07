
if [ -z $INSTALL_PREFIX ]
then
    echo "Please run the env.sh script before with the prefix directory"
    exit 1
fi

cd source/agg-2.5
make clean
CC="$CC_BASE" CFLAGS="$CFLAGS_FASTMATH" CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_FASTMATH" make

cp src/libagg.a "$INSTALL_PREFIX/lib"

rm -fr "$INSTALL_PREFIX/include/agg2"
mkdir -p "$INSTALL_PREFIX/include/agg2"
cp -R include/* "$INSTALL_PREFIX/include/agg2"

PKG_NAME=libagg

# Warning, since the 'EOF' below is unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}
libdir=\${prefix}/lib
includedir=\${prefix}/include/agg2

Name: libagg
Description: Anti-grain library
Version: 2.5.0

Libs: -L\${libdir} -lagg -lm
Cflags: -I\${includedir}
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"
