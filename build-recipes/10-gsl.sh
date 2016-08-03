curl -O "http://mirror.switch.ch/ftp/mirror/gnu/gsl/gsl-2.1.tar.gz"

rm -fr gsl-2.1
tar xzf gsl-2.1.tar.gz

cd gsl-2.1
CFLAGS=$CFLAGS_GSL ./configure --prefix=/c/fra/local
make
make install
