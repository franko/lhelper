enter_git_repository luajit https://github.com/franko/luajit.git "v$2"

# With older versions of Meson the option -Ddefault_library=static
# triggers an error. With Meson 0.53.1 it seems to be fine.
# The fix used was to add "-shared" in the options array.
build_and_install meson -Dportable=true "${@:3}"
