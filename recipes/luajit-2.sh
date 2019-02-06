set -e
LUAJIT_PACKAGE="LuaJIT-2.0.5"
LUAJIT_DIR=${LUAJIT_PACKAGE}
enter_remote_archive "${LUAJIT_DIR}" "http://luajit.org/download/${LUAJIT_PACKAGE}.tar.gz" "${LUAJIT_PACKAGE}.tar.gz" "tar xzf ARCHIVE_FILENAME"

CC=$CC_BASE make PREFIX="$INSTALL_PREFIX"
make PREFIX="$INSTALL_PREFIX" install
