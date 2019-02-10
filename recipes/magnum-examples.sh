set -e
enter_git_repository magnum-examples https://github.com/mosra/magnum-examples.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" -DWITH_SHADOWS_EXAMPLE=ON -DWITH_PRIMITIVES_EXAMPLE=ON -DWITH_VIEWER_EXAMPLE=ON -DWITH_TEXT_EXAMPLE=ON ..
cmake --build .
cmake --build . --target install
