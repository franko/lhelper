check_commands("cmake", "ninja", "git")

enter_git_repository("https://github.com/fmtlib/fmt.git", version)
build_and_install("cmake", "-DFMT_TEST=OFF", table.unpack(options))
