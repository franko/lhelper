set -e
enter_git_repository magnum-plugins https://github.com/mosra/magnum-plugins.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DWITH_FREETYPEFONT=ON ..
cmake --build .
cmake --build . --target install
