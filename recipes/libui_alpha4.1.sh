LIBUI_GIT_TAG="$2"
LIBUI_VERSION="${LIBUI_GIT_TAG}"

enter_git_repository libui https://github.com/andlabs/libui.git "$LIBUI_VERSION"

mkdir build && cd build
# Disable shared libraries because MSVC build is required.
cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DBUILD_SHARED_LIBS=OFF ..
ninja
ninja examples
ninja tester

# NB: The libraries should not be hard-coded here but should be provided by CMake.
# The SDL2 library does it and it could be used to do the same thing.
if [[ "$OSTYPE" == "linux"* ]]; then
  UI_OS_HEADER="ui_unix.h"
  UI_OS_LIBS="-lui -lgtk-3 -lgdk-3 -lpangocairo-1.0 -lpango-1.0 -latk-1.0 -lcairo-gobject -lcairo -lgdk_pixbuf-2.0 -lgio-2.0 -lgobject-2.0 -lglib-2.0 -lm -ldl"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "mingw"* ]]; then
  UI_OS_HEADER="ui_windows.h"
  UI_OS_LIBS="-lui -luser32 -lkernel32 -lgdi32 -lcomctl32 -luxtheme -lmsimg32 -lcomdlg32 -ld2d1 -ldwrite -lole32 -loleaut32 -loleacc -luuid -lwindowscodecs"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  UI_OS_HEADER="ui_darwin.h"
  UI_OS_LIBS=""
fi

cd -
mkdir -p "$DESTDIR$INSTALL_PREFIX/include"
mkdir -p "$DESTDIR$INSTALL_PREFIX/lib"
cp ui.h "$UI_OS_HEADER" "$DESTDIR$INSTALL_PREFIX/include"
cp build/out/libui.a "$DESTDIR$INSTALL_PREFIX/lib"

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
Version: ${LIBUI_VERSION}

Libs: -L\${libdir} ${UI_OS_LIBS}
Cflags: -I\${includedir}
EOF

install_pkgconfig_file "${PKG_NAME}.pc"
