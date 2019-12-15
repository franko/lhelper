enter_git_repository luajit https://github.com/franko/luajit.git "v$2"

# If the -shared option is not provided -Ddefault_library=static will
# be used and it will trigger a meson error.
# As a workaround we always add the -shared option.
options=("${@:3}")
options+=("-shared")

build_and_install meson -Dportable=true "${options[@]}"
