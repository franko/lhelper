LUAJIT_PACKAGE="LuaJIT-2.0.5"
LUAJIT_DIR=${LUAJIT_PACKAGE}
enter_remote_archive "${LUAJIT_DIR}" "http://luajit.org/download/${LUAJIT_PACKAGE}.tar.gz" "${LUAJIT_PACKAGE}.tar.gz" "tar xzf ARCHIVE_FILENAME"
inside_archive_apply_patch "luajit-2.0-windows-install-fix"

make PREFIX="$INSTALL_PREFIX"
make PREFIX="$INSTALL_PREFIX" install
