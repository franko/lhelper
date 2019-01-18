set -e
source "$LHELPER_DIR/build-helper.sh"
enter_git_repository magnum https://github.com/mosra/magnum.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_SDL2APPLICATION=ON ..
cmake --build .
cmake --build . --target install
