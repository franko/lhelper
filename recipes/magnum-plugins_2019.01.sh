enter_git_repository magnum-plugins https://github.com/mosra/magnum-plugins.git "v$2"
build_and_install cmake  -DWITH_FREETYPEFONT=ON
