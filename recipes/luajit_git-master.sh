enter_git_repository luajit https://github.com/franko/luajit.git "${2#git-}"
build_and_install meson -Dportable=true
