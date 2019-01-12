set -e
source "build-helper.sh"
enter_git_repository corrade https://github.com/mosra/corrade.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} ..
cmake --build .
cmake --build . --target install