SNDFILE_PACKAGE=libsndfile-"$2"
enter_remote_archive "$SNDFILE_PACKAGE" "http://www.mega-nerd.com/libsndfile/files/$SNDFILE_PACKAGE.tar.gz" "$SNDFILE_PACKAGE.tar.gz" "tar xzf ARCHIVE_FILENAME"
build_and_install configure --disable-{sqlite,alsa,octave} --enable-shared=no
