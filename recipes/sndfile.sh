cd downloads
curl -O "http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.28.tar.gz"
rm -fr libsndfile-1.0.28
tar xzf libsndfile-1.0.28.tar.gz

cd libsndfile-1.0.28
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" CC="$CC_BASE" CFLAGS="$CFLAGS_BASE" ./configure --prefix="$INSTALL_PREFIX" --disable-{sqlite,alsa,octave} --enable-shared=no
make

PKG_NAME=sndfile
mv "$PKG_NAME.pc" "$PKG_NAME.pc.orig"
cat "$PKG_NAME.pc.orig" | sed "s/\/c\//c:\//g" > "$PKG_NAME.pc"

make install
