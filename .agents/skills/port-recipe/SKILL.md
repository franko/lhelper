---
name: port-recipe
description: Use when porting an lhelper package recipe from the old bash format to the Lua format, or when writing a new lhelper recipe. Covers the bash→Lua translation rules, the recipe API, the index/version convention, and how to test a ported recipe.
---

# Port an lhelper recipe from bash to Lua

lhelper was a bash project; the build logic is now Lua. The original bash
recipes live in `~/dev/lhelper-recipes/` (one file per `<package>_<version>`
or `<package>_<version>+<n>`), and the new Lua recipes live in `recipes/` in
this repo. Porting the remaining recipes is the project's pending work (see
PORTING-NOTES.md). Use this skill when asked to port a recipe or to write a
new one.

## Where to look

- **Bash originals**: `~/dev/lhelper-recipes/<package>_<version>[+n]` — plain
  bash scripts. This is the source of truth for what the recipe must do.
- **Model Lua recipes** (read these first):
  - `recipes/fmt_10.0.0.lua` — minimal CMake recipe.
  - `recipes/freetype2_26.2.20.lua` — `configure` recipe with option
    pre-processing and a version lookup table.
  - `recipes/sdl2_2.28.5+2.lua` — the richest example: per-platform/per-option
    logic, `dependency`/`provides`, patches, pkg-config file install.
  - `recipes/zlib_1.3.1.lua`, `recipes/openblas_0.3.34.lua` — packages with no
    supported build system, driven with `run()` (see "Recipes without a
    supported build system" below).
- **The API**: `lua/recipe.lua` — `make_recipe_env` defines every function and
  variable the recipe has in scope (`enter_archive`, `build_and_install`,
  `check_commands`, `dependency`, `provides`, `file_replace`, ...).
- **Recipe index**: `recipes/index` — one `<package> <version>` line per
  package; see the version convention below.
- **Conventions**: `AGENTS.md` (no sed/awk, no shell for commands, keep it
  small, match the Lua style).

## The index and version convention (easy to get wrong)

The `recipes/index` line lists the **upstream** version, e.g. `pcre2 10.39`,
and the recipe file is named `<package>_<version>.lua`:

```
recipes/index              -> "pcre2 10.39"
recipes/pcre2_10.39.lua    <- matches the index line
```

`installer.latest_package_version` returns the upstream version from the
index, and `installer.find_recipe_filename` matches
`<package>_<version>.lua` (or any later `<package>_<version>+<n>.lua`
revision if one exists — see "Revision suffix" below). The `version`
variable passed to a running recipe is the upstream version (the string from
the index / spec file), so inside a recipe, `version` is what you interpolate
into download URLs:

```lua
enter_archive("https://.../pcre2-" .. version .. ".tar.gz")
```

If the upstream release tag and the lhelper version differ (e.g. freetype2
uses the libtool version `26.2.20` but the release is `2.13.3`), do what the
freetype2 recipe does: keep a lookup table in the recipe and translate
`version` -> release before building the URL.

### Revision suffix (`+N`)

A `+N` suffix on the filename (e.g. `pcre2_10.39+1.lua`) identifies a
revision of a recipe where the upstream package version stays the same — used
later to ship a tweaked recipe for an already-published package. Since the
Lua recipes are created ex-novo when porting from bash, **do not carry over
the `+N`** from the old bash filenames: name the ported recipe
`<package>_<version>.lua` and put `<version>` (no suffix) in `recipes/index`.
Add a `+N` only later, if you revise an already-ported recipe.

## bash → Lua translation rules

Recipes call the same API regardless of build system; only the option
construction differs. Map the bash constructs as follows.

### Commands / toolchain checks

```bash
check_commands make cmp diff "$CC"
```
```lua
check_commands("make", "cmp", "diff", getenv("CC"))
```

`check_commands` is a no-op in the dependency phase and verifies the command
is on `PATH` in the run phase. `build_and_install("configure", ...)` *also*
internally tests for `make`, `grep`, `cmp`, `diff`, so listing them in
`check_commands` is redundant but harmless and matches the original intent —
keep them when the bash recipe had them (the comment "configure requires cmp
and diff" is worth preserving).

### Option lists

bash arrays become Lua tables; the `options` table is provided in scope and
recipe-specific flags pass through literally to the build system:

```bash
disables=(pcre2-16 pcre2-32 debug jit ebcdic pcre2grep-{jit,callout,callout-fork})
enables=(pcre2-8 unicode newline-is-anycrlf)
for name in "${enables[@]}";  do options+=("--enable-$name");  done
for name in "${disables[@]}"; do options+=("--disable-$name"); done
```
```lua
local enables  = { "pcre2-8", "unicode", "newline-is-anycrlf" }
local disables = { "pcre2-16", "pcre2-32", "debug", "jit", "ebcdic",
    "pcre2grep-jit", "pcre2grep-callout", "pcre2grep-callout-fork" }

local opts = {}
for _, name in ipairs(enables)  do opts[#opts + 1] = "--enable-"  .. name end
for _, name in ipairs(disables) do opts[#opts + 1] = "--disable-" .. name end
```

**Bash brace expansion must be written out explicitly** — Lua has no
`a-{x,y,z}` expansion. `pcre2grep-{jit,callout,callout-fork}` becomes three
separate entries `pcre2grep-jit`, `pcre2grep-callout`, `pcre2grep-callout-fork`.

### Standard option flags (consumed by build_and_install, do not pass through)

These are *intercepted* by `build_and_install`, not forwarded to the build
tool, so never put them in your options list:

- `-shared`            → `--enable-shared --disable-static` (configure) /
  `-DBUILD_SHARED_LIBS=ON` (cmake) / `-Ddefault_library=shared` (meson)
- `-pic`               → `--with-pic=yes` / `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`
  / `-Db_staticpic=true`
- `-prefix=<path>`     → overrides `LHELPER_SYSTEM_PREFIX`
- `--buildtype=<x>`    → overrides `BUILD_TYPE`

Anything else (e.g. `--enable-unicode`, `-DBUILD_TEST=OFF`) is forwarded
verbatim. See `configure_options` / `cmake_options` / `meson_options` in
`lua/recipe.lua` for the exact interception logic.

### entering the source

```bash
enter_archive "https://.../pkg-${version}.tar.gz"
enter_git_repository "https://github.com/o/pkg.git" "$VERSION_TAG"
inside_git_apply_patch some-name        # git apply patch/<name>.patch
inside_archive_apply_patch some-name    # patch -p1 < patch/<name>.patch
```
```lua
enter_archive("https://.../pkg-" .. version .. ".tar.gz")
enter_git_repository("https://github.com/o/pkg.git", version)
inside_git_apply_patch("some-name")
inside_archive_apply_patch("some-name")
```

Binary/string interpolation uses `..`; never build shell strings. For a tag
that differs from `version`, pass the literal tag (the freetype2 lookup-table
pattern applies here too).

### building

```bash
build_and_install configure "${options[@]}"
build_and_install cmake -DBUILD_TEST=OFF "${options[@]}"
build_and_install meson "${options[@]}"
```
```lua
build_and_install("configure", table.unpack(opts))
build_and_install("cmake", "-DBUILD_TEST=OFF", table.unpack(opts))
build_and_install("meson", table.unpack(opts))
```

`build_and_install` runs the tool, applies `-j<cores>`, does `DESTDIR`
install into the environment prefix, and relocates paths. The first arg is the
build system (`"configure"`, `"cmake"`, or `"meson"`); the rest are the
extra options.

### dependencies and provides

```bash
dependency "sdl2 -opengl >=2.0.14"
dependency --optional "libpng"
provides "freetype2 = $version"
```
```lua
dependency("sdl2 -opengl >=2.0.14")
dependency("--optional", "libpng")
provides("freetype2 " .. version)
```

`dependency`/`provides` only record info during the dependencies phase; they
are safe to call unconditionally.

**Drop the `=` when porting a `provides`.** A dependency *spec* may carry a
comparator, but a `provides` is stored as a registry *entry*, whose version is
read as the first non-option word — with `provides "freetype2 = 2.13.3"` the
recorded version becomes `=` and every comparison against it is meaningless.
See the `dependency-model` skill for the matching rules.

### other API functions

- `check_commands(...)`, `test_commands(...)` → bool
- `getenv(name)`, `setenv(name, value)`
- `pkg_config(...)` → string|nil  (wraps `pkg-config`, returns trimmed output)
- `file_replace(filename, old, new)` — **use this instead of sed/awk**
- `install_pkgconfig_file(filename)` — copies a generated .pc file into the
  env's pkgconfig dir
- `run(argv)` — run an arbitrary command, logged to the recipe logs (argv
  list, never a shell string)
- `fail_config(msg)` — bails out with the "recipe configuration error" code
- `print(...)` — write to the recipe's stdout log

Variables already in scope: `version`, `options`, `platform`, `cpu_type`,
`cpu_target`, `build_type`.

## Recipes without a supported build system

`build_and_install` knows `configure`, `cmake` and `meson` only. A package
built by a plain Makefile (zlib, OpenBLAS) has to be driven with `run()`, and
then everything `build_and_install` would have done for you becomes your job:

| Handled for you | What you must do instead |
|---|---|
| `--prefix=$LHELPER_SYSTEM_PREFIX` | pass the prefix the build system's own way (`PREFIX=`, `prefix=`, ...) — and pass `getenv("LHELPER_SYSTEM_PREFIX")`, never `INSTALL_PREFIX` |
| `DESTDIR` install into the staging root | pass `DESTDIR=getenv("INSTALL_PREFIX")` yourself, or install into it explicitly |
| moving `<destdir>/usr/*` up to `<destdir>/*` | repeat the normalization block (below) |
| `-shared` / `-pic` / `-prefix=` / `--buildtype=` interception | parse them out of `options` yourself and translate them |
| `-O3`/`-g` from `build_type` (configure builds; cmake and meson get the build type as an option instead) | add them to `CFLAGS`/`CXXFLAGS` yourself (see the zlib recipe) |
| `make -j<cores>` | add it if the build system does not parallelize itself (OpenBLAS does, via its own `MAKEFLAGS += -j`) |

The normalization block, identical in `zlib_1.3.1.lua` and
`openblas_0.3.34.lua`:

```lua
local prefix = getenv("LHELPER_SYSTEM_PREFIX")
-- INSTALL_PREFIX is only set in the "run" phase; the dependencies phase
-- only evaluates the arguments of the no-op run() calls.
local destdir = getenv("INSTALL_PREFIX") or ""
...
local rel = prefix:gsub("^%a:", ""):gsub("^/", ""):gsub("/$", "")
if destdir ~= "" and rel ~= "" then
    local source_dir = destdir .. "/" .. rel
    for _, name in ipairs(util.listdir(source_dir)) do
        os.rename(source_dir .. "/" .. name, destdir .. "/" .. name)
    end
    util.rm_rf(destdir .. "/" .. rel:match("^([^/]*)"))
end
```

It is duplicated in both recipes because `normalize_destdir_install` is local
to `recipe.lua`; **if a third recipe needs it, extract it into the recipe API
instead of copying it a third time.**

Two things to get right in this kind of recipe:

- Guard for the dependencies phase. `run()` is a no-op there, but its
  *arguments are still evaluated* and `INSTALL_PREFIX` is not set yet — hence
  the `or ""` above.
- Build against the system prefix so the generated `.pc` contains `/usr/lib`,
  which is the string the relocation pass rewrites. The `prefix-relocation`
  skill explains why, and what silently breaks when you skip it.

## Recipe file header

Match the existing Lua recipes: a short comment when the bash recipe had a
worthwhile comment (e.g. "the configure script requires cmp and diff"), then
`check_commands`, then the option construction, then `enter_archive` /
`enter_git_repository`, then `build_and_install`. No shebang, no
`#!/bin/bash`. Keep it small — a plain port is usually 20-40 lines.

## Testing a ported recipe

**Critical**: building a package can upload the result to lhelper.cc. Per
AGENTS.md, `~/.config/lhelper/config` on this machine may hold the
maintainer's real SSH key. **Always fake `HOME`** for test builds so nothing
is uploaded, and never run `register key` or trigger remote upload unless the
user explicitly asks.

`tools/lhtest` does the HOME faking by construction and keeps `var/lhelper`
out of the repo — prefer it to hand-rolled environment variables:

```sh
# rebuild the binary and start from a clean sandbox
tools/lhtest -f -b list recipes            # confirms the index lookup

# a throwaway spec inside the sandbox, then an end-to-end build
# replace package-name with the recipe's package name throughout these examples
tools/lhtest -q sh 'cat > test.lhelper <<EOF
cc = getenv("CC") or "clang"
cxx = getenv("CXX") or "clang++"
build_type = "Release"
packages = { "package-name", }
EOF'
tools/lhtest -q build test.lhelper

# iterate on the recipe: lua/ and recipes/ are symlinked, so edits are live.
# "install" needs an activated environment, so source the activate script.
tools/lhtest -q sh 'bash -c "source .lhelper/test/bin/activate && lhelper install --rebuild package-name"'
```

Use `-p p2` for a second, independent project when testing another option set
in parallel.

A successful run prints `Package "package-name" successfully installed`. Then
check, under `$(tools/lhtest -q path)/proj/p1/.lhelper/test/`:

- the produced files in `include/` and the library directory (`lib/`, `lib64/`
  or a multiarch subdirectory), including any symlinks the build creates,
- the configure/cmake/meson/make invocation logged in
  `logs/package-name-stdout.log`, to confirm the option list matches the bash
  original,
- the installed `.pc` file, if any (find its directory with `pkg-config
  --variable=pcfiledir package-name` in the activated environment); its
  `libdir`/`includedir` must point at the environment prefix — not `/usr` or
  the working dir,
- `bin/lhelper-packages`, for the registry line and any `provides` lines.

Remember `--rebuild`: without it a cached package with the same recipe version
and digest is reused and your edited recipe never runs (see the `debug-build`
skill).

### Verifying the installed package actually works

Inspecting files is not proof that the library links. If the package ships a
`.pc`, write a small `probe.c` in your current directory and compile and run
it using only what `pkg-config` reports. Run the probe in bash with the
environment activated so the correct pkg-config directory is used:

```sh
e=$(tools/lhtest -q path)/proj/p1/.lhelper/test
bash -c '
  source "$1/bin/activate" || exit 1
  pkg-config --cflags --libs package-name || exit 1
  cc probe.c $(pkg-config --cflags --libs package-name) -o probe && ./probe
' bash "$e"
```

Use the `.pc` module name instead of `package-name` if they differ.

Keep the probe to a few lines calling one real entry point and printing a
result you can check by hand (a known matrix product, a parsed string, a
version string). A link failure here usually means the `.pc` is missing a
private dependency: `pkg-config --libs --static package-name` shows what
`Libs.private` adds, and a recipe may need to move one of those into `Libs`.

Clean up afterwards with `tools/lhtest reset` and remove your local probe.
Never commit the `var/lhelper/` working data (it is gitignored).

### macOS gotcha (this machine)

If configure fails with `C compiler cannot create executables` and the
config.log shows `ld64.lld: error: library not found for -lSystem`, the
machine has `ld64.lld` shadowing Apple's `/usr/bin/ld` (check `which ld`).
This is a **toolchain** problem, not a recipe problem — the recipe is fine.
Either remove/deprioritize `ld64.lld` on `PATH` or pass
`ldflags = "-fuse-ld=/usr/bin/ld"` in the `.lhelper` spec. Don't try to
"fix" it inside the recipe.

## Updating the index

After writing `recipes/<package>_<version>.lua`, add or update the line
in `recipes/index`:

```
<package> <version>                # the upstream version, no +N suffix
```

Verify with `list recipes` — the new package must appear (basename without
`.lua`), and `install <package>` must resolve to your recipe file.

## Checklist for a port

- [ ] Read the bash original in `~/dev/lhelper-recipes/`.
- [ ] Read the closest model recipe (`fmt`, `freetype2`, `sdl2`, or `zlib` /
      `openblas` when there is no supported build system).
- [ ] Write `recipes/<package>_<version>.lua` translating the bash per
      the rules above; expand brace expansions explicitly. Do **not** carry
      over a `+N` suffix from the old bash filename.
- [ ] Drop the `=` from any `provides` carried over from bash.
- [ ] Add `<package> <version>` to `recipes/index`.
- [ ] Rebuild, create a throwaway spec, and run an end-to-end build in the
      sandbox (follow "Testing a ported recipe" above).
- [ ] Inspect the configure/cmake/meson/make command in the build log; confirm
      it matches the bash recipe's option set plus the standard
      `--prefix` / shared-static / pic flags.
- [ ] If the package ships a `.pc`, check it points at the environment prefix
      and compile and run a probe against the library.
- [ ] Exercise the recipe's own options too (each `-flag` branch), not just the
      default build.
- [ ] Clean up (`tools/lhtest reset`); leave only the two repo changes (the
      recipe file and the index line).
