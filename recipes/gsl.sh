cd downloads
curl -O "http://mirror.switch.ch/ftp/mirror/gnu/gsl/gsl-2.1.tar.gz"

rm -fr gsl-2.1
tar xzf gsl-2.1.tar.gz

cd gsl-2.1
CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure --prefix="$WIN_INSTALL_PREFIX"
make
make install
