set -e
enter_git_repository corrade https://github.com/mosra/corrade.git master

mkdir build && cd build
cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" ..
cmake --build .
cmake --build . --target install
