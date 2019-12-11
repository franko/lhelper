enter_git_repository fox-1.6 https://github.com/franko/fox-1.6.git "${2#git-}"
# Support options: opengl, apps
options="$(meson_options "${@:3}")"
build_and_install meson $options
