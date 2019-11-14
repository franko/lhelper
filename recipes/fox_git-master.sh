enter_git_repository fox-1.6 https://github.com/franko/fox-1.6.git "${2#git-}"
build_and_install meson -Ddefault_library=static -Dapps=false -Dopengl=false
