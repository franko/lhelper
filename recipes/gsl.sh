set -e

GSL_VERSION=gsl-2.1
enter_remote_archive "$GSL_VERSION" "http://ftpmirror.gnu.org/gsl/${GSL_VERSION}.tar.gz" "${GSL_VERSION}.tar.gz" "tar xzf ARCHIVE_FILENAME"

./configure --prefix="$WIN_INSTALL_PREFIX" --enable-${BUILD_TYPE,,}
make
make install
