enter_git_repository magnum-examples https://github.com/mosra/magnum-examples.git "v$2"
build_and_install cmake -DWITH_SHADOWS_EXAMPLE=ON -DWITH_PRIMITIVES_EXAMPLE=ON -DWITH_VIEWER_EXAMPLE=ON -DWITH_TEXT_EXAMPLE=ON
