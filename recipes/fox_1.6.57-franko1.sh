fox_version="$2"
enter_git_repository fox-1.6 https://github.com/franko/fox-1.6.git "v${fox_version}"
build_and_install meson "${@:3}"
