# Notes on the Lua port

Date: 2026-07-19

## What was done

lhelper was rewritten from bash to Lua 5.4 while keeping the same
functionalities. The work is in commit `4fbe151`.

- Lua 5.4.8 is vendored as source code in `vendor/lua/`. The whole program
  is built by `build.sh` with a single C compiler invocation, in a few
  seconds; `install.sh` builds and installs everything. The only
  requirements are a C compiler and the basic tools (tar, curl, git, ...).
- A small C layer in `src/`:
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

As of 2026-07-22 the bash implementation has been removed; the migration
is considered complete.

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

### Install plans (2026-07-23)

The install orchestration used to compute everything about a package
twice: on activation `compute_desired_packages` ran every recipe's
dependencies phase and computed the digests to obtain the desired registry
lines, then every package actually installed went through
`library_install`, which re-ran the dependencies phase and recomputed the
digest against the on-disk registry. Convergence relied on the two
independent computations producing byte-identical lines, and
`update_installed_packages` maintained the lhelper-packages file
incrementally (a two-pointer merge of the old and new line lists, with a
skip-list to protect just-reinstalled packages) precisely to keep the
on-disk state in the shape the recomputation needed.

Now the dependencies phase runs once per package: `prepare_install_plan`
returns an install *plan* (parsed spec, recipe location, declared
dependencies, usage lines, digest, registry line) and
`execute_install_plan` builds or reuses the package archive using the
planned values, so what is registered is exactly what was planned and the
environment converges by construction. `update_installed_packages` became
a plain set reconciliation: remove the files of the packages whose line is
no longer desired, then walk the plans in order, re-registering the
unchanged ones and installing the missing ones. Creating a new environment
is the same reconciliation against an empty registry, so `main.lua` no
longer has its own install loop. Deleted with the change: the merge and
its skip-list, the registry-line-to-install-arguments conversion
(`package_of_line`) and the `run_mode` dual dispatch of `library_install`.
Small behavior deltas: files of removed or changed packages are deleted
before any install instead of interleaved with them, and the registry is
rewritten from the plans on every activation (which also heals stray
lines).

### Removal of the edit/reload cycle

The interactive `lhelper edit` / `lhelper reload` restart mechanism was
dropped from the Lua version. It used to edit the `build.lhelper` of the
active environment and respawn the subshell in place (SIGUSR1 to the shell,
`exit 11`, and an environment-restart loop in `activate`). To change an
active environment now, exit the subshell, edit the `build.lhelper` file and
activate it again. Removed with the feature: the `edit` and `reload`
commands, `signal_environment_restart`, the `activate` restart loop and its
env snapshot/restore, the `LHELPER_BUILD_FILENAME` variable, and the
`LHELPER_SHELL_PID` export plus the SIGUSR1 trap in `lhelper-bash-init`. The
bash implementation keeps the feature untouched.

## Known gaps (not implemented)

1. **Untested platforms.** Only macOS was actually exercised. The Linux
   and MSYS2 code paths are written (per-platform code in `lhsys.c`,
   `build.sh`, `env.lua`, the sdl2 recipe) but have not been run on those
   systems.
2. ~~**No cleanup of partial downloads on Ctrl-C.**~~ Done (2026-07-22).
   `lhsys.c` now exposes `arm_interrupt` / `disarm_interrupt` /
   `interrupted`: while a download runs the SIGINT handler only records the
   signal (so the interrupted `spawn` returns), and `recipe.lua`'s
   `download_guarded` then removes the partial file or git checkout and
   exits with the "interrupted" code (4). Outside a download the default
   SIGINT disposition is restored, so Ctrl-C still terminates lhelper
   immediately. This mirrors the SIGINT trap of the original bash version.

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
- ~~**Implement the download interruption cleanup**~~ Done (2026-07-22, see gap 2).
- ~~**Decide the fate of the bash implementation.**~~ Done (2026-07-22):
  removed `lhelper`, `build-helper.sh`, `common-lhelper.sh`,
  `cpu-lhelper.sh`, `create-env.sh`, `src/`, the old `install` and
  `install-github`; folded `README-lua.md` into `README.md`; renamed
  `csrc/` to `src/`.
- **Update the install-from-github path.** `install-github` was removed; a
  new version should install the Lua version (`install.sh`) instead.
- **Minor leftovers.**
  - `lhelper list environments` is mentioned in the README but was not
    implemented in bash nor in Lua; either implement it or fix the
    documentation.
  - ~~The `tests/` directory~~ Removed with the bash implementation.
