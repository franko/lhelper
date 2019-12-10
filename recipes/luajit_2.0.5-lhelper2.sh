enter_git_repository luajit https://github.com/franko/luajit.git "v$2"
build_and_install meson -Dportable=true
