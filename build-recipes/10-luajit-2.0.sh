LUAJIT_PACKAGE="LuaJIT-2.0.4"
LUAJIT_DIR=${LUAJIT_PACKAGE}

curl -O "http://luajit.org/download/${LUAJIT_PACKAGE}.tar.gz"

rm -fr "${LUAJIT_DIR}"
tar xzf "${LUAJIT_PACKAGE}.tar.gz"

cd "${LUAJIT_DIR}"
INSTALL_PREFIX_ESCAPE=${INSTALL_PREFIX//\//\\\/}
cat Makefile | sed "s/^export PREFIX=.*/export PREFIX= ${INSTALL_PREFIX_ESCAPE}/g" > "Makefile.tmp" && mv Makefile.tmp Makefile
export CC=$CC_BASE
CC=$CC_BASE PREFIX=$INSTALL_PREFIX make
PREFIX=$INSTALL_PREFIX make install
cp src/lua51.dll "$INSTALL_PREFIX/bin"

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
