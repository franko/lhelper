# Notes on the Lua port

Date: 2026-07-19

## What was done

lhelper was rewritten from bash to Lua 5.4 while keeping the same
functionalities. The work is in commit `4fbe151`.

- Lua 5.4.8 is vendored as source code in `vendor/lua/`. The whole program
  is built by `build.sh` with a single C compiler invocation, in a few
  seconds; `install.sh` builds and installs everything. The only
  requirements are a C compiler and the basic tools (tar, curl, git, ...).
- A small C layer in `csrc/`:
  - `main.c` embeds the Lua interpreter, locates the install prefix from
    the executable path and runs the main script;
  - `lhsys.c` provides the OS facilities missing from the Lua standard
    library: mkdir, stat, listdir, realpath, setenv, environ and a
    `spawn(argv)` function that runs commands *without going through a
    shell* (fork/exec on POSIX, CreateProcess on Windows), so there is no
    shell quoting anywhere.
- The lhelper logic is implemented as Lua modules in `lua/`: command
  dispatch (`main.lua`), install orchestration, digests and remote
  packages (`install.lua`), the recipe API (`recipe.lua`), environment
  creation (`env.lua`), package registry and spec matching (`pkg.lua`),
  CPU targets (`cpu.lua`), prefix relocation (`pathreplace.lua`) and a
  pure-Lua MD5 (`md5.lua`).
- The former C helper tools (`lh-path-replace`, `lh-sort`, `lh-cmp`,
  `lh-realpath`) are absorbed by the Lua code. GNU sed, awk and md5sum are
  no longer needed. Bash is used only for the environment activation
  subshell and the generated `activate`/`lhelper-config` scripts.
- The `.lhelper` spec files are now simple Lua scripts (lowercase
  variables: `cc`, `cxx`, `cflags`, `cpu_type`, `build_type`,
  `packages`, ...). `lhelper create -e` still generates a commented
  template with the CPU help for the current machine.
- Recipes are now Lua scripts (see `README-lua.md` for the API). Two
  recipes were ported as the first-phase samples: `freetype2` and `sdl2`
  (the most complex one, with all its per-platform and per-option logic).
- Verified on macOS (arm64): environment creation, building freetype2 and
  sdl2 from source, activation subshell, compiling and running a real
  SDL+FreeType program inside the environment, prefix relocation, saved
  package reuse, remote package download/upload with lhelper.cc, install /
  remove / list commands, spec file change with package add/removal on
  reload, missing-dependency detection.

The bash implementation is left in place; the two implementations coexist
until the migration is considered complete.

### In-memory state (commit `72b6c15`)

The bash implementation used files as inter-process communication with the
recipe processes and the environment subshells: `logs/<pkg>-dependencies`,
`logs/<pkg>-provides`, `logs/<pkg>-usage` and a temporary on-disk
environment (`.lhelper/.tmp`) created only to compare its
`lhelper-packages` and `lhelper-config` files with the real environment's
ones. Since the recipes now run in-process, all of this was replaced by
plain Lua values: the recipes' dependencies phase returns its declarations
directly, and the desired state of an environment (registry lines and
config content) is computed in memory from the build spec. The only files
left are the genuinely persistent ones: the `lhelper-packages` registry,
the per-package `.list` files, the archives/packages/digests caches and
the build logs. The digest computation was verified to be unchanged.

## Known gaps (not implemented)

1. **Untested platforms and the edit/reload cycle.** Only macOS was
   actually exercised. The Linux and MSYS2 code paths are written
   (per-platform code in `lhsys.c`, `build.sh`, `env.lua`, the sdl2
   recipe) but have not been run on those systems. Likewise the
   interactive `lhelper edit` / `lhelper reload` restart cycle (SIGUSR1 to
   the environment shell, exit code 11, environment restart) is ported —
   `lhelper-bash-init` now exports `LHELPER_SHELL_PID` for this — but was
   not tested interactively.
2. **No cleanup of partial downloads on Ctrl-C.** The bash implementation
   trapped SIGINT during downloads and removed the partially downloaded
   archive or git checkout. The Lua implementation does not install a
   signal handler yet: interrupting lhelper during a download can leave a
   partial file in `var/lhelper/archives`, which would then be picked up
   as a (corrupt) cached archive on the next run. Workaround: delete the
   file by hand. A proper fix is a small SIGINT handler in `lhsys.c` plus
   a cleanup hook in `recipe.lua`, or downloading to a `.part` name and
   renaming on success (probably the simplest and most robust option).

## What remains to be done to complete the porting

- **Port the recipe collection.** Only freetype2 and sdl2 exist in the new
  format. The full set lives in `external/lhelper-recipes` (bash format)
  and must be converted recipe by recipe. The translation is mechanical
  for simple recipes (`enter_archive` + `build_and_install`); the ones
  with heavy option parsing need the sdl2 recipe as a model. Decide also
  where the Lua recipes will live: the current `recipes/` directory in
  this repository, or a new branch/repository replacing
  `franko/lhelper-recipes` so that `lhelper update recipes` keeps working
  (the command is ported and expects a git checkout).
- **Test on Linux and MSYS2** (see gap 1) and fix what surfaces. On MSYS2
  the points to watch are: path translation (`LH_MSYSROOT`, `/c/` vs
  `C:/`), the `spawn` Windows implementation, and the temporary directory
  (`C:/Windows/Temp`).
- **Implement the download interruption cleanup** (see gap 2).
- **Decide the fate of the bash implementation.** Once the recipes are
  ported and the platforms verified: remove `lhelper`, `build-helper.sh`,
  `common-lhelper.sh`, `cpu-lhelper.sh`, `create-env.sh`, `src/`, the old
  `install` and `install-github`, fold `README-lua.md` into `README.md`,
  and update `lhelper-completion.bash` if the command set changed.
- **Update the install-from-github path.** `install-github` still
  installs the bash version; it should build and install the Lua version
  (`install.sh`) instead.
- **Minor leftovers.**
  - `lhelper list environments` is mentioned in the README but was not
    implemented in bash nor in Lua; either implement it or fix the
    documentation.
  - The `tests/` directory contains fixtures for the old
    `lh-path-replace` C tool; they could be reused for a small Lua test
    of `pathreplace.lua`.
  - Packages built by the Lua version use a slightly different digest
    input (MACHTYPE format differs), so they will not be shared with the
    ones built by the bash version on lhelper.cc. This is harmless but
    worth knowing while both versions are in use.
