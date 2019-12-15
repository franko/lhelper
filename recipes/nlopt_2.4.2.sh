NLOPT_VERSION="$2"
enter_remote_archive "nlopt-$NLOPT_VERSION" "https://github.com/stevengj/nlopt/releases/download/nlopt-$NLOPT_VERSION/nlopt-$NLOPT_VERSION.tar.gz" "nlopt-$NLOPT_VERSION.tar.gz" "tar xzf ARCHIVE_FILENAME"
build_and_install configure "${@:3}"
