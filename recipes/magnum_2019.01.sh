enter_git_repository magnum https://github.com/mosra/magnum.git "v$2"
build_and_install cmake -DWITH_SDL2APPLICATION=ON
