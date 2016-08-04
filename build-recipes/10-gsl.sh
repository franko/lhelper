curl -O "http://mirror.switch.ch/ftp/mirror/gnu/gsl/gsl-2.1.tar.gz"

rm -fr gsl-2.1
tar xzf gsl-2.1.tar.gz

cd gsl-2.1
CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure "--prefix=$INSTALL_PREFIX"
make
make install

PKG_NAME=gsl

export WIN_INSTALL_PREFIX=${INSTALL_PREFIX/\/c\//c:\/}
WIN_INSTALL_PREFIX=${WIN_INSTALL_PREFIX//\//\\\/}
cat "${BUILD_DIR}/$PKG_NAME.pc.build" | sed "s/BUILD_PREFIX_DIR/$WIN_INSTALL_PREFIX/g" > "$PKG_NAME.pc"
cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
