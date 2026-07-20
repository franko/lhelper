check_commands("meson", "ninja", "git")

-- implot's meson build links the imgui SDL2 + OpenGL3 backends and the imgui
-- demo (the imguisdl2/imguiopengl3/imguidemo pkg-config files produced by the
-- imgui build with -sdl2 -opengl3) and sdl2 itself. Those pkg-config files are
-- not separate registry packages, so we cannot depend on them directly;
-- instead we require imgui to be built with the backends that produce them,
-- and require sdl2. This turns a mid-build meson failure into lhelper's
-- missing-dependency report.
dependency("imgui", "-largeidx", "-sdl2", "-opengl3")
dependency("sdl2", "-opengl")
dependency("glad", "-loader")

enter_git_repository("https://github.com/franko/implot.git", "v" .. version .. "-lhelper")
build_and_install("meson", table.unpack(options))
