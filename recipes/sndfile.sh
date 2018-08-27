cd downloads
curl -O "http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.28.tar.gz"
rm -fr libsndfile-1.0.28
tar xzf libsndfile-1.0.28.tar.gz

cd libsndfile-1.0.28
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure --prefix="$WIN_INSTALL_PREFIX" --disable-{sqlite,alsa,octave} --enable-shared=no
make
make install
