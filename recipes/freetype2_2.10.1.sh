FREETYPE_VERSION="$2"
enter_remote_archive "freetype-${FREETYPE_VERSION}" "http://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" "freetype-${FREETYPE_VERSION}.tar.gz" "tar xf ARCHIVE_FILENAME"
build_and_install configure --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no "${@:3}"
