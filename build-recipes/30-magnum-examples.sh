set -e

rm -fr magnum-examples
git clone https://github.com/mosra/magnum-examples.git

cd magnum-examples
mkdir build && cd build
cmake -G "Ninja" -DCMAKE_PREFIX_PATH=${INSTALL_PREFIX} -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} -DWITH_SHADOWS_EXAMPLE=ON -DWITH_PRIMITIVES_EXAMPLE=ON -DWITH_VIEWER_EXAMPLE=ON ..
cmake --build .
cmake --build . --target install
