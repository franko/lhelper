LUAJIT_PACKAGE="LuaJIT-2.0.5"
LUAJIT_DIR=${LUAJIT_PACKAGE}

cd downloads
curl -O "http://luajit.org/download/${LUAJIT_PACKAGE}.tar.gz"

rm -fr "${LUAJIT_DIR}"
tar xzf "${LUAJIT_PACKAGE}.tar.gz"

cd "${LUAJIT_DIR}"
cat Makefile | sed "s/^export PREFIX=.*/export PREFIX= ${WIN_INSTALL_PREFIX}/g" > "Makefile.tmp" && mv Makefile.tmp Makefile
export CC=$CC_BASE
CC=$CC_BASE PREFIX=$INSTALL_PREFIX make
PREFIX=$INSTALL_PREFIX make install
cp src/lua51.dll "$INSTALL_PREFIX/bin"
