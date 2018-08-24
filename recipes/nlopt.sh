cd downloads
# curl -L -O "http://ab-initio.mit.edu/nlopt/nlopt-2.4.2.tar.gz"
curl -L -O "https://github.com/stevengj/nlopt/releases/download/nlopt-2.4.2/nlopt-2.4.2.tar.gz"

rm -fr nlopt-2.4.2
tar xzf nlopt-2.4.2.tar.gz

cd nlopt-2.4.2
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure "--prefix=$INSTALL_PREFIX"

make
make install

