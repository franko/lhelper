enter_git_repository agg https://github.com/franko/agg.git "v$2"
build_and_install meson "${@:3}"
