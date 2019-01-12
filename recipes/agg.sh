set -e
source "build-helper.sh"

enter_git_repository agg https://github.com/franko/agg.git master

mkdir build && cd build
meson --prefix="$INSTALL_PREFIX" --buildtype=release ..
ninja
ninja install

PKG_NAME=libagg

# Warning, since the 'EOF' below is unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}
libdir=\${prefix}/lib
includedir=\${prefix}/include/agg2

Name: libagg
Description: Anti-grain library
Version: 2.5.0

Libs: -L\${libdir} -lagg -lm
Cflags: -I\${includedir}
EOF

cp "$PKG_NAME.pc" "$INSTALL_PREFIX/lib/pkgconfig"
