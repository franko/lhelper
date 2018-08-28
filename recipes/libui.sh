cd downloads
rm -fr libui
git clone https://github.com/andlabs/libui.git
cd libui

git checkout alpha4

mkdir build && cd build
# Disable shared libraries because MSVC build is required.
cmake -G "Ninja" -DBUILD_SHARED_LIBS=OFF ..

ninja
ninja examples
