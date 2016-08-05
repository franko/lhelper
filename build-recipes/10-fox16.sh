cd fox-1.6.52
# echo CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" ./configure --prefix=/c/fra/local --enable-release --with-opengl=no --with-xft=no
cd src
make clean
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_FOX" make

cd -
cp src/libfox16.a "$INSTALL_PREFIX/lib"
rm -fr "$INSTALL_PREFIX/include/fox-1.6"
mkdir -p "$INSTALL_PREFIX/include/fox-1.6"
cp include/*.h "$INSTALL_PREFIX/include/fox-1.6"

PKG_NAME=fox16

export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}
WIN_INSTALL_PREFIX=${WIN_INSTALL_PREFIX//\//\\\/}
cat "$PKG_NAME.pc.build" | sed "s/BUILD_PREFIX_DIR/$WIN_INSTALL_PREFIX/g" > "$PKG_NAME.pc"
cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
