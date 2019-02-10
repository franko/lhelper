set -e
SNDFILE_PACKAGE=libsndfile-1.0.28
enter_remote_archive "$SNDFILE_PACKAGE" "http://www.mega-nerd.com/libsndfile/files/$SNDFILE_PACKAGE.tar.gz" "$SNDFILE_PACKAGE.tar.gz" "tar xzf ARCHIVE_FILENAME"

./configure --prefix="$WIN_INSTALL_PREFIX" --enable-${BUILD_TYPE,,} --disable-{sqlite,alsa,octave} --enable-shared=no
make
make install
