# AGENTS.md

Guidance for AI coding agents (Claude Code, opencode, etc.) working in this repository.

## What this is

**lhelper** is a small utility for compiling C and C++ libraries on Linux, Windows
(MSYS2) and macOS. It reads per-package build instructions ("recipes"), knows the
common build systems (Make, CMake, Autotools/configure, Meson), and creates isolated
*environments*, each holding a set of libraries built with a specific compiler and
flags.

The project is a **Lua 5.4 rewrite** of a former bash implementation. The bash version
has been fully removed (as of commit `906c076`); the Lua port is now the whole project.
See [PORTING-NOTES.md](PORTING-NOTES.md) for the history and remaining work, and
[README.md](README.md) for user-facing docs.

## Architecture

The program is a single self-contained executable: a C host embeds a vendored Lua
interpreter and runs the lhelper logic, which lives entirely in Lua modules.

- `vendor/lua/` — vendored **Lua 5.4** sources. No external Lua dependency; do not
  add package managers or third-party Lua libs.
- `src/` — the thin C layer:
  - `main.c` embeds Lua, locates the install prefix from the executable path, sets a
    few globals (`LHELPER_EXE_PATH`, `LHELPER_LUA_DIR`, `arg`), and runs `main.lua`.
  - `lhsys.c` exposes the `lhsys` module: `mkdir`, `rmdir`, `chdir`, `getcwd`,
    `setenv`, `environ`, `listdir`, `stat`, `realpath`, `spawn`,
    `arm_interrupt` / `disarm_interrupt` / `interrupted`, and `platform`.
    `spawn(argv)` runs commands **without a shell** (fork/exec on POSIX,
    CreateProcess on Windows) — so there is no shell quoting anywhere. The
    `*_interrupt` trio lets `recipe.lua` catch Ctrl-C during a download and
    clean up the partial file (see `download_guarded`).
- `lua/` — the lhelper program:
  - `main.lua` — CLI parsing and command dispatch (start here).
  - `install.lua` — install orchestration, digests, remote package download/upload.
  - `recipe.lua` — the recipe API (`enter_archive`, `build_and_install`, ...).
  - `env.lua` — environment creation and `activate`-script generation.
  - `pkg.lua` — package registry and package-spec matching.
  - `cpu.lua` — known CPU targets and compiler flags.
  - `pathreplace.lua` — install-prefix relocation in built files.
  - `md5.lua` — pure-Lua MD5 (replaces the external `md5sum`).
  - `util.lua` — filesystem/process/string helpers, built on `lhsys`.
- `recipes/` — the Lua recipes plus an `index` file listing the latest version of
  each package. Recipe files are named `<name>_<version>.lua`.
- `patch/` — `.patch` files applied by some recipes.
- `lhelper-bash-init` — the init file for the environment subshell.

## Build and run

Only a C compiler and basic unix tools (tar, gzip, git, curl, pkg-config, make) are
required.

```sh
# Compile build/lhelper from vendored Lua + src/
sh build.sh

# Run from the source tree WITHOUT installing (dev mode).
# Working data goes in ./var/lhelper and the repo dir is used as prefix.
LHELPER_LUA_DIR="$PWD/lua" ./build/lhelper <command> ...

# Full install (builds, then copies runtime files to <prefix>)
sh install.sh <prefix>
```

There is **no test suite** and **no CI** — verify changes by running the binary in dev
mode. The build is a single C-compiler invocation and takes a few seconds.

## Commands (see `lua/main.lua`)

`create` / `activate` (with `-e`/`--edit`, `--packages`), `install`
(`--local`, `--rebuild`), `remove`, `list (files|packages|recipes)`, `update recipes`,
`register key <ssh-key> <port>`, `env-source`, `cleanup`, `dir`.

## Spec files and recipes

- A **`.lhelper` spec file** is a plain Lua script setting lowercase variables:
  `cc`, `cxx`, `cflags`, `cxxflags`, `ldflags`, `cpu_type`, `cpu_target`,
  `build_type` (`"Release"`/`"Debug"`), and a `packages` list. It runs in a
  restricted sandbox (`getenv`, `os`, `string` only). `lhelper create -e <name>`
  generates a commented template. The `packages` list needs only the libraries
  used directly: missing dependencies are resolved and installed automatically
  (`resolve_install_plans` in `install.lua`).
- A **recipe** is a Lua script run with the recipe API in scope (`version`,
  `options`, `platform`, `cpu_type`, `cpu_target`, `build_type` are provided).
  Key functions: `check_commands`, `dependency`/`provides`, `enter_archive`,
  `enter_git_repository`, `inside_*_apply_patch`, `build_and_install`,
  `install_pkgconfig_file`, `file_replace`, `run`, `pkg_config`, `getenv`/`setenv`.
  Use `recipes/sdl2_2.28.5+2.lua` as the model for complex per-platform/per-option
  logic; `recipes/fmt_10.0.0.lua` for a minimal one.

## Conventions and constraints

These are deliberate choices by the maintainer — respect them:

- **Keep it simple.** Small, dependency-free, single-binary. Don't add build systems,
  package managers, or frameworks.
- **No `sed` / `awk`** — they have macOS/GNU incompatibilities. Do text work in Lua
  (`util.lua`, `file_replace`, `pathreplace.lua`).
- **No shell for running commands** — always go through `lhsys.spawn` / `util` helpers
  (argv lists), never string-interpolated shell commands. Bash is used *only* for the
  environment activation subshell and the generated `activate`/`lhelper-config`
  scripts.
- **Recipes are not sandboxed against malicious code** — no hardening effort is spent
  there; recipes are trusted input.
- Match the existing Lua style: `local` module tables, `require`, plain `for _, x in
  ipairs(...)` loops, explicit error messages + `os.exit(1)`.

## Platform status

Verified on **macOS (arm64)** only. The Linux and MSYS2 code paths exist (in
`lhsys.c`, `build.sh`, `env.lua`, and the sdl2 recipe) but have **not been run** on
those systems. On MSYS2, watch path translation (`LH_MSYSROOT`, `/c/` vs `C:/`), the
Windows `spawn`, and the temp dir. See "Known gaps" in PORTING-NOTES.md.

## Pending work

- Port the rest of the recipe collection (only a handful exist in the new Lua format;
  the full set is in bash form in `external/lhelper-recipes`).
- Test on Linux and MSYS2.

## ⚠️ Important: do not upload packages during testing

`~/.config/lhelper/config` on this machine holds the maintainer's **real lhelper.cc
SSH upload key** (`LH_SSH_KEY_PATH` / `LH_SSH_KEY_PORT`). Building packages can upload
the results to lhelper.cc. When running builds for testing, **fake `HOME`** (or
otherwise ensure no config with an SSH key is picked up) so nothing is uploaded to the
real server. Avoid the `register key` command and anything that triggers remote upload
unless the user explicitly asks for it.
