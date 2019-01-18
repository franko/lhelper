set -e
source "$LHELPER_DIR/build-helper.sh"
enter_git_repository libgit2 https://github.com/libgit2/libgit2.git "v0.27.7"

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX ..

cmake --build .
cmake --build . --target install

