set -e
source "$LHELPER_DIR/build-helper.sh"

NLOPT_VERSION=nlopt-2.4.2
enter_remote_archive "$NLOPT_VERSION" "https://github.com/stevengj/nlopt/releases/download/nlopt-2.4.2/$NLOPT_VERSION.tar.gz" "$NLOPT_VERSION.tar.gz" "tar xzf ARCHIVE_FILENAME"

CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure --prefix="$WIN_INSTALL_PREFIX"

make
make install
