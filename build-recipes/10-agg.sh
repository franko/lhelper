
cd agg-2.5
make clean
CC="$CC_BASE" CFLAGS="$CFLAGS_AGG" CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_AGG" make

cp src/libagg.a "$INSTALL_PREFIX/lib"

rm -fr "$INSTALL_PREFIX/include/agg2"
mkdir -p "$INSTALL_PREFIX/include/agg2"
cp -R include/* "$INSTALL_PREFIX/include/agg2"

PKG_NAME=libagg

export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}
WIN_INSTALL_PREFIX=${WIN_INSTALL_PREFIX//\//\\\/}
cat "$PKG_NAME.pc.build" | sed "s/BUILD_PREFIX_DIR/$WIN_INSTALL_PREFIX/g" > "$PKG_NAME.pc"
cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
