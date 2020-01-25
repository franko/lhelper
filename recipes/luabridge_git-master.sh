luabridge_install () {
    mkdir build && pushd build
    cmake -G "Ninja" -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" ..
    cmake --build .
    popd
    mkdir -p "$INSTALL_PREFIX/include"
    cp -r Source/LuaBridge "$INSTALL_PREFIX/include"
}

enter_git_repository LuaBridge https://github.com/vinniefalco/LuaBridge.git "${2#git-}" --recurse-submodules
luabridge_install
