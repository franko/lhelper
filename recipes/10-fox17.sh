# curl -O "http://ftp.fox-toolkit.org/pub/fox-1.7.56.zip"
# rm -fr fox-1.7.56
# unzip fox-1.7.56.zip

cd fox-1.7.56
# echo CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" ./configure --prefix=/c/fra/local --enable-release --with-opengl=no --with-xft=no
cd lib
make clean
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" make

cd -
cp lib/libfox.a "$INSTALL_PREFIX/lib/libfox17.a"
rm -fr "$INSTALL_PREFIX/include/fox-1.7"
mkdir -p "$INSTALL_PREFIX/include/fox-1.7"
cp include/*.h "$INSTALL_PREFIX/include/fox-1.7"

PKG_NAME=fox17

export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}
WIN_INSTALL_PREFIX=${WIN_INSTALL_PREFIX//\//\\\/}
cat "$PKG_NAME.pc.build" | sed "s/BUILD_PREFIX_DIR/$WIN_INSTALL_PREFIX/g" > "$PKG_NAME.pc"
cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
