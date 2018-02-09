curl -L -O "https://github.com/wxWidgets/wxWidgets/releases/download/v3.1.0/wxWidgets-3.1.0.tar.bz2"

PROJ_SOURCE_DIR=wxWidgets-3.1.0

rm -fr $PROJ_SOURCE_DIR
tar xjvf wxWidgets-3.1.0.tar.bz2

cd $PROJ_SOURCE_DIR
CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure "--prefix=$INSTALL_PREFIX"

# replace string like:
# BK_DEPS = /c/fra/src/wxwidgets/bk-deps
# with:
# BK_DEPS = c:/fra/src/wxwidgets/bk-deps
find . -name 'Makefile' -exec sed -i 's/= *\/c\//= c:\//g' '{}' \;

make
make install

touch "${BUILD_DIR}/${SCRIPT_NAME}.build-complete"
