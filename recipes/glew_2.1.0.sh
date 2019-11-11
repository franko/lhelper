enter_git_repository glew https://github.com/nigels-com/glew.git "v$2"

echo "Applying patch glew-remove-nostdlib-flag"
inside_git_apply_patch "glew-remove-nostdlib-flag"

export GLEW_DEST="${INSTALL_PREFIX}"

make extentions
make all
make install.all
