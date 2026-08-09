check_commands("meson", "ninja", getenv("CC"))

-- We use "lhelper" to differentiate from the releases from official repository.
enter_git_repository("https://github.com/franko/luajit.git", "v" .. version .. "-lhelper")

-- With older versions of Meson the option -Ddefault_library=static
-- triggers an error. With Meson 0.53.1 it seems to be fine.
-- The fix used was to add "-shared" in the options array.
build_and_install("meson", table.unpack(options))
