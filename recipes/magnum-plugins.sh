set -e
source "build-helper.sh"
enter_git_repository magnum-plugins https://github.com/mosra/magnum-plugins.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_FREETYPEFONT=ON ..
cmake --build .
cmake --build . --target install
