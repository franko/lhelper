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

### Recipes preferred to the system libraries (2026-08-01)

A dependency provided by a system library used to be taken from the system
even when lhelper had a recipe for it, so an environment silently depended
on what was installed on the machine. `dependency_status` now consults the
system libraries only when the recipes index has no recipe for the package,
so a missing dependency is installed in the environment whenever lhelper
can build it. The previous behaviour is available with the spec file's
`prefer_system_libraries`, `true` for every package or a list of package
names; when it applies and the system version does not satisfy the
requirement the install stops with an error, as before, instead of falling
back to the recipe.

The option is written in the environment's `lhelper-config` as
`LHELPER_PREFER_SYSTEM_LIBRARIES` ("*" or the names separated by spaces),
so `library_check_and_install` resolves the dependencies of `lhelper
install` the same way through `active_env_config()`. The export line is
written only when the option is used, so the environments created before
this change still match their configuration file and are not recreated from
scratch; the names are sorted, so their order in the spec file does not
change the configuration. Recipe existence alone decides, not the recipe
version: when the available version does not satisfy the dependency the
error reporting it is the same as for any other unsatisfiable dependency.
Optional dependencies ("?name") are unchanged: they are never installed and
keep using a system library when there is one.

### Automatic dependencies resolution (2026-07-29)

The `packages` list of a spec file used to be the complete list of the
packages to install, dependencies included: a package requiring something
not already in the list made lhelper stop with a "Found missing packages"
report. The dependencies are now resolved automatically. The install plan
computation was split in two, `begin_install_plan` (recipe lookup and
dependencies phase) and `complete_install_plan` (usage lines, digest and
registry line), so that the packages needed by a dependency can be planned
in between: `resolve_plans_pass` walks the requested packages depth-first,
adding the dependencies that neither the registry nor a system library
provides, with the options of the dependency spec, before the package
requiring them. An explicitly requested package always takes the place of
an automatically added one, wherever it appears in the list, so the spec
file no longer has to be in dependency order.

When two packages need the same automatically added dependency with
different options, the options are accumulated and the whole resolution is
run again (`resolve_install_plans`); the accumulated set grows strictly at
every pass, so this terminates. The `install` command resolves the same
way against the packages of the activated environment. Dependency cycles
are detected and reported.

Fixed with the change, in `pkg.test_package_spec`: the version of a
registry line, "<name> [options] <version> <digest>", was taken from its
*last* word, the digest, so every version-constrained dependency on an
installed package failed; and `pkg.vercomp` now compares the leading
number of a version component, so a recipe version like "2.28.5+2"
compares equal to "2.28.5" instead of lower.

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
  `C:/`), running from a MINGW64 shell (see the dedicated section below),
  and the temporary directory (`C:/Windows/Temp`). Note that there is no
  longer a Windows-specific `spawn`: `lhsys.c` is POSIX-only and the MSYS2
  runtime provides the emulation.
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

## Running from a MINGW64 shell: POSIX → Windows path conversion

Added 2026-08-08. The problem was confirmed by code inspection and fixed
the same day (see "The fix" below), but none of it has run on a real MSYS2
box yet: the fix is speculative and must be verified together with the
rest of the MSYS2-runtime work.

### The intended setup

lhelper is now an MSYS program (linked against `msys-2.0.dll`,
built with the MSYS2 gcc), but it is meant to be **run from a MINGW64
shell**, so that the packages it builds are native mingw64 ones. This is
not a workaround: the MINGW64 shell *is* `/usr/bin/bash.exe`, itself an
MSYS program, started with `MSYSTEM=MINGW64` so that the profile prepends
`/mingw64/bin` to `PATH`. lhelper therefore sits in the same category as
`make`, `git` or `sed` — an MSYS tool driving a native mingw64 toolchain.
The MSYS2 gcc is a build-time requirement for lhelper itself only, and
never builds any package.

Two things were checked against this model and are already correct:

- `util.which` (`lua/util.lua:262`) splits `PATH` on `:` and relies on the
  runtime resolving `name` to `name.exe` in `stat`. Right, because the
  parent shell is an MSYS process, so `PATH` is inherited in POSIX form
  with no conversion.
- `main.lua:150` starts the activation subshell as
  `bash --init-file <lhelper-bash-init>`, deliberately **not** a login
  shell. This matters: `bash -l` would re-run `/etc/profile`, which
  rebuilds `PATH` from `MSYSTEM` and would discard the `PATH` entries the
  activated environment just added. The subshell inherits `MSYSTEM` and
  stays a MINGW64 environment.

### The problem (confirmed by inspection)

lhelper now works in POSIX paths (`getcwd` returns `/home/user/...` or
`/c/...`), while the compilers it spawns are native and understand only
Windows paths. The runtime converts argv and a few known environment
variables automatically when spawning a native child, but it cannot
convert:

- paths that lhelper **writes into a file** (generated activate scripts,
  `.pc` files, cmake toolchain files) — nothing rewrites those later;
- paths buried inside a compound value such as `CC="gcc -I/home/..."`,
  where conversion would have to happen on a substring; the argv heuristic
  may or may not catch it, which is precisely the kind of thing not to
  rely on.

Two sites did the conversion by hand, insufficiently:

- `lua/install.lua:151` — `win_prefix = prefix_dir:gsub("^/c/", "c:/")`,
  which feeds `WIN_INSTALL_PREFIX` (used by recipes, i.e. likely written
  into files).
- `lua/recipe.lua:571` — `env_prefix = env_prefix:gsub("^/c/", "C:/")`,
  which feeds the `-I` and `-L` flags added to `CC`, `CXX` and `LDFLAGS`.

Both only matched a `/c/` prefix. Running from a MINGW64 shell the
environment prefix is normally under `/home/<user>/...`, i.e.
`C:/msys64/home/<user>/...`, which the pattern does not match at all: the
POSIX path was then passed through unchanged.

The inspection also showed that the bash implementation had exactly the
same `/c/`-only substitution (`WIN_INSTALL_PREFIX="${INSTALL_PREFIX/#\/c\//c:\/}"`)
and the same `lh-path-replace` variant logic: the Lua port is faithful. It
presumably worked in practice because the environments lived under `/c/...`
project directories, where the substitution does match.

Two more defects of the same class were found in the same pass:

- `to_real_prefix` (`lua/recipe.lua:55`), contrary to what was first
  thought, was *not* a correct model: it prepended `LH_MSYSROOT` to every
  absolute path, so `/c/foo` (a cygdrive path, not under the msys root)
  became `C:/msys64/c/foo`; and the concatenation was only correct if
  `cygpath -m /` ends with a slash.
- At package build time (`lua/install.lua:830`) the prefix occurrences are
  replaced with `__LHELPER_PREFIX__` using the POSIX `/usr` as the search
  pattern. But a native cmake or meson receives the prefix converted by the
  runtime, so the generated `.pc` files contain `C:/msys64/usr`; matching
  the `/usr` substring inside it corrupts them into
  `C:/msys64__LHELPER_PREFIX__`. `pathreplace.pattern_variants` generates
  all the forms (`c:/`, `C:/`, `/c/` and the `LH_MSYSROOT`-stripped POSIX
  one) only when the pattern is given with a drive letter — evidence the
  caller was always meant to pass the Windows form on Windows.

### The fix (2026-08-08, speculative — not yet run on MSYS2)

The preferred option was implemented: `lhsys.winpath()` exposes
`cygwin_create_path(CCP_POSIX_TO_WIN_A, ...)` from `<sys/cygwin.h>` (the
runtime's own mount-table lookup, handling `/c/`, `/home/`, `/usr/` and any
custom `/etc/fstab` mount), with backslashes flipped to `/` — the "mixed"
form of `cygpath -m`. `util.winpath()` wraps it, an identity on the other
platforms, and its comment states the convention: POSIX paths for
lhelper's own file operations and for the MSYS tools; `winpath` for a path
handed to a native program in a form the runtime's spawn conversion cannot
rewrite (written into a file a native tool reads, or inside a compound
value such as `CC="gcc -I/..."`). Converted sites:

- `set_prefix_variables` (`install.lua`): `WIN_INSTALL_PREFIX` is now the
  real Windows form of the environment prefix.
- `add_lhelper_env_directory` (`recipe.lua`): the `-I`/`-L` flags appended
  to `CC`, `CXX` and `LDFLAGS`.
- `to_real_prefix` (`recipe.lua`): delegates to `winpath`, fixing the two
  defects above.
- The build-time relocation (`install.lua`) passes
  `util.winpath(spec.package_prefix)` as the search pattern, activating the
  `pattern_variants` machinery so both the native-tool (`C:/msys64/usr`)
  and configure-script (`/usr`) forms are replaced.
- `LH_MSYSROOT` is now set from `util.winpath("/")` instead of spawning
  `cygpath -m /`. Note: no trailing slash, while `cygpath` may emit one;
  the only remaining consumer (`pathreplace.pattern_variants`) handles
  both forms.

Also implemented in the same pass: lhelper on Windows now refuses to run
when `MSYSTEM` is unset or `MSYS`, since from a
plain MSYS shell `cc = getenv("CC") or "gcc"` would silently resolve to
the MSYS `/usr/bin/gcc` and every package would be built against
`msys-2.0.dll`. Deriving the default compiler from the `MSYSTEM` prefix
(`UCRT64` → `/ucrt64/bin/gcc`, ...) was left out for now.

Verified on macOS: build, `list recipes`, environment creation with a
remote package, and a from-source `install --rebuild` (which runs the
converted relocation and cmake code paths as identities). To verify on a
real MSYS2 box: the whole thing, plus that `cygwin_create_path` is
declared by the MSYS2 `<sys/cygwin.h>` as used here.

### One smaller thing still to look at

- `msys2-runtime.md:74-105` is stale: it still describes `spawn` as calling
  `CreateProcessA` directly and says `util.lua` reads `PATH` with `;`. Both
  described the native Win32 implementation and are false since the
  MSYS2-runtime rework. Fix it before using that document as a reference
  for the MSYS2 work. (The file is not tracked in git yet.)
