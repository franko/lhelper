enter_git_repository lua https://github.com/franko/lua.git "v$2"
build_and_install meson "${@:3}"
