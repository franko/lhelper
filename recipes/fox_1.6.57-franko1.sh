fox_version="$2"
enter_git_repository fox-1.6 https://github.com/franko/fox-1.6.git "v${fox_version}"
# Support options: opengl, apps
options="$(meson_options "${@:3}")"
build_and_install meson $options
