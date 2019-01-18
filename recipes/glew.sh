set -e
source "$LHELPER_DIR/build-helper.sh"
enter_git_repository glew https://github.com/nigels-com/glew.git master

echo "Applying patch glew-remove-nostdlib-flag"
inside_git_apply_patch "glew-remove-nostdlib-flag"

export CC="$CC_BASE"
export CFLAGS="$CFLAGS_FASTMATH"
export CXX="$CXX_BASE"
export CXXFLAGS="$CXXFLAGS_FASTMATH"
export GLEW_DEST="${INSTALL_PREFIX}"

make extensions
make all
make install.all
