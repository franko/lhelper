set -e

NLOPT_VERSION=nlopt-2.4.2
enter_remote_archive "$NLOPT_VERSION" "https://github.com/stevengj/nlopt/releases/download/nlopt-2.4.2/$NLOPT_VERSION.tar.gz" "$NLOPT_VERSION.tar.gz" "tar xzf ARCHIVE_FILENAME"

./configure --prefix="$WIN_INSTALL_PREFIX" --enable-${BUILD_TYPE,,}

make
make install
