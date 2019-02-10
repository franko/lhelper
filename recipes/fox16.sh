FOX_ARCHIVE_NAME=fox-1.6.57

if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
    FOX_WITH_X=no
    FOX_WITH_XFT=no
else
    FOX_WITH_X=yes
    FOX_WITH_XFT=yes
fi

enter_remote_archive "${FOX_ARCHIVE_NAME}" "http://fox-toolkit.org/ftp/${FOX_ARCHIVE_NAME}.tar.gz" "${FOX_ARCHIVE_NAME}.tar.gz" "tar xzf ARCHIVE_FILENAME"
inside_archive_apply_patch fox-1.6-configure-library-fix-2
build_and_install configure --with-opengl=no --disable-shared --with-x=$FOX_WITH_X --disable-bz2lib --with-xft=$FOX_WITH_XFT
