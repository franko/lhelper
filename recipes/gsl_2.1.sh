GSL_VERSION="gsl-$2"
enter_remote_archive "$GSL_VERSION" "http://ftpmirror.gnu.org/gsl/${GSL_VERSION}.tar.gz" "${GSL_VERSION}.tar.gz" "tar xzf ARCHIVE_FILENAME"
build_and_install configure "${@:3}"
