enter_git_repository sol2 https://github.com/ThePhD/sol2.git "v$2"

python3 single/single.py

_sol_include_dir="$INSTALL_PREFIX/include/sol"
mkdir -p "$_sol_include_dir"
cp single/include/sol/sol.hpp "$_sol_include_dir"
cp single/include/sol/forward.hpp "$_sol_include_dir"

PKG_NAME=sol2

# Warning, since the 'EOF' below is unquoted shell variables substitutions
# will be done on the text body. The '$' should be therefore escaped to
# avoid shell substitution when needed.
cat << EOF > $PKG_NAME.pc
prefix=${WIN_INSTALL_PREFIX}
includedir=\${prefix}/include

Name: ${PKG_NAME}
Description: Sol2 C++ to Lua API wrapper
Version: $2

Libs: 
Cflags: -I\${includedir}
EOF

install_pkgconfig_file "${PKG_NAME}.pc"
