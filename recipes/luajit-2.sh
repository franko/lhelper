set -e
source "$LHELPER_DIR/build-helper.sh"
LUAJIT_PACKAGE="LuaJIT-2.0.5"
LUAJIT_DIR=${LUAJIT_PACKAGE}
enter_remote_archive "${LUAJIT_DIR}" "http://luajit.org/download/${LUAJIT_PACKAGE}.tar.gz" "${LUAJIT_PACKAGE}.tar.gz" "tar xzf ARCHIVE_FILENAME"

cat Makefile | sed "s/^export PREFIX=.*/export PREFIX= ${WIN_INSTALL_PREFIX}/g" > "Makefile.tmp" && mv Makefile.tmp Makefile
export CC=$CC_BASE
CC=$CC_BASE PREFIX=$INSTALL_PREFIX make
PREFIX=$INSTALL_PREFIX make install
cp src/lua51.dll "$INSTALL_PREFIX/bin"
