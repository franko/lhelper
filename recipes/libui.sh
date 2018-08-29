cd downloads
rm -fr libui
git clone https://github.com/andlabs/libui.git
cd libui

git checkout alpha4

mkdir build && cd build
# Disable shared libraries because MSVC build is required.
cmake -G "Ninja" -DBUILD_SHARED_LIBS=OFF ..

ninja
ninja examples
ninja tester

cd -
cp ui.h ui_windows.h "$INSTALL_PREFIX/include"
cp build/out/libui.a "$INSTALL_PREFIX/lib"

PKG_NAME=libui

# Warning, since the 'EOF' below is unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ${PKG_NAME}
Description: Simple and portable GUI library in C
Version: 0-alpha4

Libs: -L\${libdir} -lui -luser32 -lkernel32 -lgdi32 -lcomctl32 -luxtheme -lmsimg32 -lcomdlg32 -ld2d1 -ldwrite -lole32 -loleaut32 -loleacc -luuid -lwindowscodecs
Cflags: -I\${includedir}
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"
