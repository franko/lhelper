---
name: prefix-relocation
description: Use when a recipe installs files by hand (no build_and_install), when an installed .pc/.cmake/-config file points at the wrong directory, when the "prefix directory found in binary files" warning appears, or when writing a recipe whose build system bakes absolute paths into its output. Covers the three prefixes, the /usr → __LHELPER_PREFIX__ → environment pipeline, and which files are silently left untouched.
---

# How a package becomes relocatable

An lhelper package is built once and installed into many environments, each
with a different prefix. Nothing about the build knows the final directory:
packages are built against a fixed fake prefix, the fake prefix is rewritten
to a token before the package is archived, and the token is rewritten to the
real environment prefix at install time. A recipe that installs files by hand
has to fit into that pipeline, and it is easy to fit into it *almost*
correctly — the failure is silent.

## The three prefixes

| Variable | Value | Meaning |
|---|---|---|
| `LHELPER_SYSTEM_PREFIX` | `/usr` (`lua/main.lua:37`) | The prefix the package is **configured and built** for. Never a real destination. A package spec option `-prefix=<path>` overrides it per package (`parse_install_args`). |
| `INSTALL_PREFIX` | during a build: `<LHELPER_WORKING_DIR>/tmp`; during install: the environment prefix (`install.lua:773`, `:858`) | The **staging root** (a DESTDIR) while the recipe runs. Re-pointed at the environment before the archive is extracted. |
| `LHELPER_ENV_PREFIX` | `<...>/.lhelper/<name>` | The environment the files finally land in. |
| `WIN_INSTALL_PREFIX` | `util.winpath(INSTALL_PREFIX)` | The Windows form of the above, written into `.pc` and config files where a native compiler must resolve it. |
| `CONFIG_PREFIX` | `spec.package_prefix` (`install.lua:774`) | The build prefix, exported for recipes that need it verbatim. |

`LHELPER_WORKING_DIR` is `<lhelper-prefix>/var/lhelper`; in dev mode that is
`./var/lhelper` in the source tree.

## The pipeline

```
recipe builds with --prefix=/usr, installs with DESTDIR=<staging>
   ↓  files land in <staging>/usr/{include,lib,...}
normalize: move <staging>/usr/* up to <staging>/*
   ↓
library_dir_reloc(<staging>, winpath("/usr"), "__LHELPER_PREFIX__")
   ↓  rewrites text files that reference the build prefix
tar czf <pkg>_<recipe-version>_<digest>.tar.gz -C <staging> .
   ↓  (this archive is what gets cached and uploaded)
untar into a temp dir, library_dir_reloc(.., "__LHELPER_PREFIX__", WIN_INSTALL_PREFIX)
   ↓
cp -a into the environment prefix, write the package's file list
```

Both relocation passes are the same function (`install.lua:176`), so whatever
it does not rewrite on the way in, it will not rewrite on the way out either.

## What actually gets rewritten — and what does not

`library_dir_reloc` walks the tree and only considers a file when its name
matches one of **four** patterns (`install.lua:182`):

- ends with `.pc`
- ends with `-config`
- contains `/config/` anywhere in the path (this is for wxwidgets'
  `lib/wx/config/*`)
- ends with `.la`

**Everything else is skipped in silence.** In particular a CMake package
config — `lib/cmake/<name>/<Name>Config.cmake` — matches none of them. That is
the trap: if the build system writes an absolute prefix into its `.cmake`
files, the package ships pointing at `/usr` and nothing warns you. It is only
safe when upstream writes the file self-relative, as OpenBLAS does:

```cmake
file(REAL_PATH "../../.." _OpenBLAS_ROOT_DIR BASE_DIRECTORY ${CMAKE_CURRENT_LIST_DIR})
SET(OpenBLAS_INCLUDE_DIRS ${_OpenBLAS_ROOT_DIR}/include)
```

So after adding a recipe, **grep the staged tree for the build prefix** and
look at what turns up outside those four patterns (see "Verifying" below).

## The warning you may see

```
warning: prefix directory "..." found in binary files:
```

`pathreplace.replace` treats a file as binary when a NUL byte appears in its
first 1024 bytes, and then refuses to patch it; it reports failure *only if*
the prefix actually occurs inside. The warning therefore means: "a file that
should have been relocatable has the build prefix compiled into it" —
typically a static library or an executable built with `-DPREFIX=...`. It
never fires for a file the four patterns did not select in the first place.

## How the path matching works

`pattern_variants` (`lua/pathreplace.lua:73`) expands the prefix before
searching, which is what makes MSYS2 work:

- A prefix starting with a drive letter is matched as `c:/...`, `C:/...` and
  `/c/...` — the three forms a build system may have written.
- When `LH_MSYSROOT` is set and the prefix starts with it (e.g.
  `C:/msys64/usr`), the MSYS-root-stripped form (`/usr`) is matched too.
- A prefix with no drive letter is matched literally.

A match only counts when the character right after it is not alphanumeric,
`-` or `_`, so `/usr` does not match inside `/usrlocal`.

This is why the build-time pass passes `util.winpath(spec.package_prefix)`
(`install.lua:831`) rather than the raw `/usr`: giving it the Windows form
lets the variant expansion derive the POSIX one, not the other way round.

## The recipe author's contract

When you use `build_and_install`, all of this is handled. When you drive the
build yourself with `run()` (see the plain-Makefile section of the
`port-recipe` skill), you must do three things:

1. **Build against `LHELPER_SYSTEM_PREFIX`**, not against `INSTALL_PREFIX`.
   The generated `.pc` must contain `/usr/lib`, because that is the string the
   relocation pass looks for. Installing directly into the staging root
   "to skip a step" bakes an absolute temp path into the package.
2. **Install with the staging root as DESTDIR**, i.e. `INSTALL_PREFIX`. In the
   dependencies phase `INSTALL_PREFIX` is not set yet, so read it as
   `getenv("INSTALL_PREFIX") or ""` and skip the move when empty.
3. **Normalize**: move `<staging>/<prefix-rel>/*` up into `<staging>/`. The
   private copy of `normalize_destdir_install` (`recipe.lua:76`) does this for
   the supported build systems; `recipes/zlib_1.3.1.lua` and
   `recipes/openblas_0.3.34.lua` repeat it inline.

Note the `msys` argument of `normalize_destdir_install`: cmake and meson pass
`true` because a *native* tool expands `/usr` to `C:/msys64/usr` on its own,
while configure passes `false`. A hand-written recipe on Windows has to know
which of the two its build system behaves like.

## Two related fixups that run after the recipe

- `fix_pkgconfig_install` (`install.lua:212`) moves a `lib/pkgconfig` or
  `share/pkgconfig` directory into `$LHELPER_LIBDIR/pkgconfig` when the
  environment's libdir is not `lib` (e.g. `lib64`). Do not hand-place `.pc`
  files to work around a libdir mismatch; use `install_pkgconfig_file`, which
  targets `LHELPER_PKGCONFIG_RPATH`.
- The file list written at install time (`<env>/packages/<n>/<pkg>.list`) is
  what `lhelper remove` deletes. Files created outside the staging root are
  not in it and will never be removed.

## Verifying

After a sandboxed build (`tools/lhtest`), check the *installed* environment:

```sh
e=$(tools/lhtest -q path)/proj/p1/.lhelper/<env>
grep -rl "__LHELPER_PREFIX__" "$e"            # must print nothing
grep -rIl "/usr/\(lib\|include\)" "$e"        # leftover build prefix: suspicious
cat "$e/lib/pkgconfig/<pkg>.pc"               # libdir/includedir → the env prefix
```

A `.pc` whose `libdir` still says `/usr/lib` means the relocation never saw the
file; a `.pc` pointing at `<working-dir>/tmp` means the recipe built against
the staging root instead of the system prefix.

## Checklist for a hand-installing recipe

- [ ] Configure/build with `getenv("LHELPER_SYSTEM_PREFIX")` as the prefix.
- [ ] Install with `DESTDIR=getenv("INSTALL_PREFIX")`, guarded for the
      dependencies phase.
- [ ] Move `<destdir>/<prefix-rel>/*` into `<destdir>/`.
- [ ] Grep the installed environment for the build prefix and for
      `__LHELPER_PREFIX__`.
- [ ] If the package ships `.cmake` config files, open them and confirm they
      are self-relative — nothing else will catch it.
