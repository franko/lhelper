cd source/fox-1.6.52
# echo CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_BASE" ./configure --prefix=/c/fra/local --enable-release --with-opengl=no --with-xft=no
cd src
make clean
CXX="$CXX_BASE" CXXFLAGS="$CXXFLAGS_FOX" make

cd -
cp src/libfox16.a "$INSTALL_PREFIX/lib"
rm -fr "$INSTALL_PREFIX/include/fox-1.6"
mkdir -p "$INSTALL_PREFIX/include/fox-1.6"
cp include/*.h "$INSTALL_PREFIX/include/fox-1.6"

PKG_NAME=fox

cat << EOF > ${PKG_NAME}.pc
prefix=${WIN_INSTALL_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/fox-1.6
LIBS=-lpthread
X_LIBS=
X_BASE_LIBS=-lcomctl32 -lwsock32 -lwinspool -lmpr -lgdi32 -limm32
X_EXTRA_LIBS=
GL_LIBS=
FOX_LIBS=-lfox16

Name: FOX
Description: The FOX Toolkit
URL: www.fox-toolkit.org
Version: 1.6.52
Libs: -L\${libdir} \${FOX_LIBS} \${X_BASE_LIBS}
Libs.private: \${X_LIBS} \${X_BASE_LIBS} \${X_EXTRA_LIBS} \${GL_LIBS} \${LIBS}
Cflags: -I\${includedir}
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"

