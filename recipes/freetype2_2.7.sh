FREETYPE_VERSION="$2"
enter_remote_archive "freetype-${FREETYPE_VERSION}" "http://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" "freetype-${FREETYPE_VERSION}.tar.gz" "tar xzf ARCHIVE_FILENAME"

pic_option="OFF"
while [ ! -z ${3+x} ]; do
    case $3 in
        -shared | -pic)
            pic_option="ON"
            ;;
    esac
    shift
done
         
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DWITH_ZLIB=OFF -DWITH_BZip2=OFF -DWITH_PNG=OFF -DCMAKE_DISABLE_FIND_PACKAGE_HarfBuzz=TRUE -DCMAKE_POSITION_INDEPENDENT_CODE=$pic_option ..
cmake --build .
cmake --build . --target install

if [ "$BUILD_TYPE" == "Debug" ]; then
    ftlibname=freetyped
else
    ftlibname=freetype
fi

PKG_NAME=freetype2

# Warning, since the 'EOF' below in unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}

Name: Freetype2
Description: Freetype2 library
Version: ${FREETYPE_VERSION}
Libs: -L\${prefix}/lib -l$ftlibname
Cflags: -I\${prefix}/include/freetype2
EOF

install_pkgconfig_file "${PKG_NAME}.pc"
