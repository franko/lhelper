FREETYPE_VERSION="2.7"

cd downloads
# Use the "-L" flag to follow redirects.
curl -L -O "http://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz"

rm -fr "freetype-${FREETYPE_VERSION}"
tar xzf "freetype-${FREETYPE_VERSION}.tar.gz"

cd "freetype-${FREETYPE_VERSION}"
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH="${INSTALL_PREFIX}" -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" -DWITH_ZLIB=OFF -DWITH_BZip2=OFF -DWITH_PNG=OFF -DCMAKE_DISABLE_FIND_PACKAGE_HarfBuzz=TRUE ..
cmake --build .
cmake --build . --target install

PKG_NAME=freetype2

# Warning, since the 'EOF' below in unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}

Name: Freetype2
Description: Freetype2 library
Version: ${FREETYPE_VERSION}
Libs: -L\${prefix}/lib -lfreetype
Cflags: -I\${prefix}/include
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"
