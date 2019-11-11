NLOPT_VERSION="nlopt-$2"
enter_remote_archive "$NLOPT_VERSION" "https://github.com/stevengj/nlopt/releases/download/nlopt-$NLOPT_VERSION/$NLOPT_VERSION.tar.gz" "$NLOPT_VERSION.tar.gz" "tar xzf ARCHIVE_FILENAME"
build_and_install configure --disable-shared
