set -e

FOX_ARCHIVE_NAME=fox-1.6.57

cd downloads
curl -O "http://fox-toolkit.org/ftp/${FOX_ARCHIVE_NAME}.tar.gz"
rm -fr "${FOX_ARCHIVE_NAME}"
tar xzf "${FOX_ARCHIVE_NAME}.tar.gz"

cd "${FOX_ARCHIVE_NAME}"

CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_FOX" ./configure --with-opengl=no --enable-release --disable-shared --with-x=no --disable-bz2lib --with-xft=no --prefix="${INSTALL_PREFIX}"
make
make install
