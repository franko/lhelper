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
provides("freetype2 = " .. version)
```

`dependency`/`provides` only record info during the dependencies phase; they
are safe to call unconditionally.

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

Run from the source tree (no install needed):

```sh
# rebuild the binary (fast, a few seconds)
sh build.sh

# dev mode: working data goes in ./var/lhelper, repo dir is the prefix
LHELPER_LUA_DIR="$PWD/lua" ./build/lhelper list recipes   # confirms index lookup

# end-to-end build with a throwaway spec and a fake HOME
mkdir -p /tmp/lh-test && cat > /tmp/lh-test/test.lhelper <<'EOF'
cc  = getenv("CC") or "clang"
cxx = getenv("CXX") or "clang++"
build_type = "Release"
packages = { "<package>", }
EOF

rm -rf /tmp/fakehome && mkdir -p /tmp/fakehome
HOME=/tmp/fakehome \
LHELPER_LUA_DIR="$PWD/lua" \
LHELPER_ENV_ROOT=/tmp/lh-test \
./build/lhelper create /tmp/lh-test/test.lhelper
```

A successful run prints `Package "<package>" successfully installed`. Check
the produced files under `/tmp/lh-test/.lhelper/test/{include,lib}/...` and
the configure/meson/cmake invocation logged in
`/tmp/lh-test/.lhelper/test/logs/<package>-stdout.log` to confirm the option
list matches the bash original. Optionally compile and run a tiny program
against the static lib to confirm it link/works.

Clean up test artifacts afterward (`rm -rf /tmp/lh-test /tmp/fakehome var/lhelper/archives/* var/lhelper/packages/2 var/lhelper/digests/*`),
and never commit the `var/lhelper/` working data (it is gitignored).

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
- [ ] Read the closest model recipe (`fmt`, `freetype2`, or `sdl2`) for the
      build system you need.
- [ ] Write `recipes/<package>_<version>.lua` translating the bash per
      the rules above; expand brace expansions explicitly. Do **not** carry
      over a `+N` suffix from the old bash filename.
- [ ] Add `<package> <version>` to `recipes/index`.
- [ ] Rebuild (`sh build.sh`) and run an end-to-end build with a faked `HOME`.
- [ ] Inspect the configure/cmake/meson command in the build log; confirm it
      matches the bash recipe's option set plus the standard
      `--prefix` / shared-static / pic flags.
- [ ] Clean up test artifacts; leave only the two repo changes (the recipe
      file and the index line).