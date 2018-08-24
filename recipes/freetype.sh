FREETYPE_VERSION="2.7"

cd downloads
# Use the "-L" flag to follow redirects.
curl -L -O "http://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz"

rm -fr "freetype-${FREETYPE_VERSION}"
tar xzf "freetype-${FREETYPE_VERSION}.tar.gz"

cd "freetype-${FREETYPE_VERSION}"
mkdir build && cd build
cmake -G "Ninja" ..
ninja || exit 1

cd -

cp build/libfreetype.a "$INSTALL_PREFIX/lib"
cp include/ft2build.h "$INSTALL_PREFIX/include"
cp -R include/freetype "$INSTALL_PREFIX/include"
cp build/include/freetype/config/ftconfig.h "$INSTALL_PREFIX/include/freetype/config"
cp build/include/freetype/config/ftoption.h "$INSTALL_PREFIX/include/freetype/config"

PKG_NAME=freetype2

# Warning, since the 'EOF' below in unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=BUILD_PREFIX_DIR

Name: Freetype2
Description: Freetype2 library
Version: ${FREETYPE_VERSION}
Libs: -L\${prefix}/lib -lfreetype
Cflags: -I\${prefix}/include
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

