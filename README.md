# lhelper

A simple utility to help you compile C and C++ libraries on Linux, Windows
(using MSYS2) and Mac OS X. lhelper reads the build instructions of each
package and knows about the most common build systems like Make, CMake,
Autotools (configure) and Meson.

It helps simplify development by creating separate environments each
containing a collection of libraries compiled using a specific compiler and
compiler flags.

## Layout

- `vendor/lua/` — vendored Lua 5.4 sources (no external dependency).
- `src/` — the C layer: `main.c` embeds Lua and runs the main script,
  `lhsys.c` provides mkdir, stat, listdir, realpath, setenv and a spawn
  function that runs commands without going through a shell.
- `lua/` — the lhelper program as Lua modules:
  - `main.lua` — command line parsing and command dispatch
  - `install.lua` — package install orchestration and environment updates
  - `recipe.lua` — the recipe API (enter_archive, build_and_install, ...)
  - `env.lua` — environment creation, activate script generation
  - `pkg.lua` — package registry and package spec matching
  - `cpu.lua` — known CPU targets and compiler flags
  - `pathreplace.lua` — prefix relocation in installed files
  - `md5.lua` — pure Lua MD5 (replaces the md5sum dependency)
  - `util.lua` — filesystem/process/string helpers
- `recipes/` — the Lua recipes (currently freetype2 and sdl2) and the
  `index` file with the latest version of each package.

The former C helper tools (`lh-path-replace`, `lh-sort`, `lh-cmp`,
`lh-realpath`) are absorbed by the Lua code. GNU sed, awk and md5sum are no
longer needed; bash is used only for the environment activation subshell.

## Build and install

Only a C compiler and the basic unix tools are required:

```sh
sh install.sh <prefix>
```

This compiles `build/lhelper` (via `build.sh`) and copies the runtime files
in `<prefix>/bin` and `<prefix>/share/lhelper`. Works on Linux, macOS and
Windows/MSYS2.

To run lhelper from the source tree without installing:

```sh
sh build.sh
LHELPER_LUA_DIR="$PWD/lua" ./build/lhelper <command> ...
```

In this mode the repository directory itself is used as prefix (the working
data goes in `./var/lhelper`).

## The spec file (.lhelper)

The build spec file is now a simple Lua script:

```lua
cc = getenv("CC") or "gcc"
cxx = getenv("CXX") or "g++"
-- cflags = ""
-- cpu_type = "x86-64"
-- cpu_target = "nehalem"
build_type = "Release"

packages = {
    "freetype2",
    "sdl2 -opengl",
}
```

`lhelper create -e <name>` generates a commented template with the CPU
targets available for the current machine.

### Dependencies

The `packages` list only needs the libraries used directly: the packages
required by a recipe and not provided by the list itself are added
automatically, and installed before the package requiring them. Listing a
package explicitly is still useful to choose its
options or its version: the explicit entry is always used, wherever it
appears in the list, and the packages depending on it are installed after
it. When two packages require the same automatically added dependency with
different options, the union of the options is used.

For example, with the recipes requiring `sdl2 -opengl`, `imgui -largeidx
-opengl3 -sdl2` and `glad -loader`:

```lua
packages = {
    "implot",
}
```

installs `sdl2`, `imgui`, `glad` and `implot`, while

```lua
packages = {
    "sdl2 -opengl -joystick",
    "implot",
}
```

installs the same packages, with the joystick support added to `sdl2`.

The same happens with `lhelper install <package>` in an activated
environment: the dependencies missing from the environment are installed
first. A package already installed with options that do not satisfy a
requirement is instead reported as an error: rebuilding it with different
options is done by changing the spec file and activating the environment
again.

### System libraries

A dependency for which lhelper has a recipe is always built and installed
in the environment, even when the system provides the same library, so that
the environment does not depend on what happens to be installed on the
machine. A system library is used only for the packages lhelper has no
recipe for.

The variable `prefer_system_libraries` asks for the opposite, using the
system library when there is one and falling back to the recipe otherwise:

```lua
-- every package, or a list of names: { "zlib", "openssl" }
prefer_system_libraries = true
```

The system library version still has to satisfy the requirement of the
recipe using it, otherwise the install stops with an error. The setting is
part of the environment configuration, so `lhelper install <package>` in
the activated environment resolves the dependencies the same way; changing
it in the spec file recreates the environment.

## Recipes

Recipes are Lua scripts run with the API functions in scope. The variables
`version`, `options` (the list of the not yet consumed options), `platform`
("linux", "darwin" or "windows"), `cpu_type`, `cpu_target` and `build_type`
are available. The main functions:

- `check_commands(...)` — fail if a required command is missing
- `dependency(spec)`, `provides(spec)` — declare dependencies/virtual packages
- `enter_archive(url [, {curl_options=..., extract_options=...}])`
- `enter_git_repository(url, tag)`
- `inside_git_apply_patch(name)`, `inside_archive_apply_patch(name)`
- `build_and_install("configure"|"cmake"|"meson", opt1, opt2, ...)`
- `install_pkgconfig_file(filename)`
- `file_replace(filename, old_text, new_text)` — literal text replacement
- `fail_config(msg)` — abort with a recipe configuration error
- `run{...}` — run an arbitrary command (argv list), output to the logs
- `pkg_config(...)` — run pkg-config and return its output
- `getenv(name)`, `setenv(name, value)`

A minimal recipe looks like:

```lua
enter_git_repository("https://github.com/mosra/magnum.git", "master")
build_and_install("cmake", "-DWITH_SDL2APPLICATION=ON")
```
