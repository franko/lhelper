set -e

GSL_VERSION=gsl-2.1
enter_remote_archive "$GSL_VERSION" "ftp://ftp.gnu.org/gnu/gsl/${GSL_VERSION}.tar.gz" "${GSL_VERSION}.tar.gz" "tar xzf ARCHIVE_FILENAME"

CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure --prefix="$WIN_INSTALL_PREFIX"
make
make install
