---
name: msys2-test-env
description: Use when building, running or testing lhelper on Windows. The agent's default shell is Git-for-Windows bash, which has no compiler; this skill shows how to run every command in a real MSYS2 MINGW64 environment (gcc, g++, make, cmake, ninja, pkg-config), plus the MSYS2-specific traps that make builds fail in confusing ways.
---

# Run and test lhelper on Windows (MSYS2 MINGW64)

On this machine the agent's `bash` tool does **not** run in MSYS2. It runs
**Git for Windows** bash, whose root `/` is `C:\NSS\git`. That shell has
`git`, `curl` and `tar`, but **no `gcc`, `g++`, `make`, `cmake`, `ninja` or
`pkg-config`** — so `sh build.sh` and every lhelper build fails there.

The real toolchain is in the separate MSYS2 installation at `C:\msys64`.
Every build/test command must be forwarded into a **MINGW64 login shell** of
that installation.

## The one rule: wrap every command

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc 'cd /home/AbbateF/dev/lhelper && <command>'
```

- `MSYSTEM=MINGW64` selects the mingw64 (native x86_64 GCC) subsystem.
- `-l` (**login** shell) is mandatory: `/etc/profile` is what builds the
  `/mingw64/bin:/usr/bin:...` PATH from `MSYSTEM`. With plain `-c` the shell
  inherits the Git-bash PATH and the toolchain is invisible.
- `/etc/profile` always `cd`s to `$HOME`, so **always `cd` explicitly**.
  `CHERE_INVOKING=1` does not help here.

### Path translation between the two shells

| | Git bash (agent default) | MSYS2 MINGW64 |
|---|---|---|
| `/` | `C:\NSS\git` | `C:\msys64` |
| repo | `/c/msys64/home/AbbateF/dev/lhelper` | `/home/AbbateF/dev/lhelper` |
| `/tmp` | `C:\NSS\git\tmp` | `C:\msys64\tmp` |

Windows paths (`/c/...`) mean the same thing in both. Use `cygpath -u` /
`cygpath -w` inside MSYS2 when unsure. The file-reading/editing tools work on
`C:\msys64\home\AbbateF\dev\lhelper\...` regardless of the shell.

### Sanity check

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc 'which gcc g++ make cmake ninja pkg-config; gcc --version | head -1'
```
Expected: `/mingw64/bin/gcc`, `/mingw64/bin/g++`, `/usr/bin/make`,
`/mingw64/bin/cmake`, `/mingw64/bin/ninja`, `/mingw64/bin/pkg-config`,
GCC 15.x. `meson` is **not** installed, so meson recipes cannot be tested.

Building lhelper itself additionally needs the **MSYS2 gcc** in
`/usr/bin/gcc` (package `gcc` of the msys subsystem: `pacman -S gcc`). It is
separate from `/mingw64/bin/gcc`, which builds the *packages*.

## Build

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc 'cd /home/AbbateF/dev/lhelper && sh build.sh'
```
Produces `build/lhelper.exe`, an **MSYS binary** linked against the MSYS2
runtime (`msys-2.0.dll`) — `build.sh` selects `/usr/bin/gcc` by itself and
refuses a MinGW compiler. Being an MSYS program is what gives lhelper the
runtime's POSIX emulation: shebang handling when spawning scripts
(`./configure`), POSIX→Windows argv/env conversion when spawning native
programs (cmake, ninja, pkgconf), and `:`-separated path lists everywhere.
It also means `lhelper.exe` only runs where `msys-2.0.dll` is on the PATH,
i.e. from an MSYS2 shell.

## Test a recipe end to end

Use `tools/lhtest` (see AGENTS.md — it fakes `HOME` so the maintainer's real
lhelper.cc upload key is never in scope). **Always clean the build root
first** (see "Trap 2" below):

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc '
  cd /home/AbbateF/dev/lhelper &&
  tools/lhtest -b create demo --packages freetype2'
```

Inspect the result, and the build logs when something fails:

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc '
  cd /home/AbbateF/dev/lhelper &&
  tools/lhtest -q sh "ls -R .lhelper/demo/lib; tail -40 .lhelper/demo/logs/<pkg>-stderr.log"'
```

Verified working on this machine: `freetype2` (configure/make path) and
`fmt` (cmake + ninja path).

## Traps specific to MSYS2 — read before debugging a failure

### Trap 1: the build root is `/tmp/build` and is shared

`LHELPER_TMPDIR` is `$TMPDIR` (or `/tmp`), which in MSYS2 is
`C:\msys64\tmp`, so every sandbox and every project shares `/tmp/build`. It
is wiped at the *start* of each build (`clean_build_root` in
`lua/recipe.lua`) and left in place afterwards, so after a failure you can
go and inspect the source tree there — but only until the next build starts.

Deleting files there must keep working; if it ever stops, you get an
explicit `error: cannot remove "..."` instead of a build that silently runs
in a half-deleted tree. Historically the failure surfaced as a baffling
`bash: ./configure: No such file or directory` — see Trap 2.

### Trap 2: Windows refuses to delete read-only files

Win32 `DeleteFile` fails on any file carrying the read-only attribute, and
build systems produce those routinely (freetype generates
`builds/unix/freetype2.pc` with mode `0444`). The MSYS2 runtime's `unlink()`
— what `lhsys.remove`, and with it `util.rm_rf`, ends up calling — handles
the attribute itself, exactly like MSYS2's `rm -rf` does. If a file still
cannot be removed, `util.rm_rf` reports it (`error: cannot remove "..."`)
instead of letting the next build run in a half-deleted tree.

### Trap 3: `ln -s` makes deep copies

Without the Windows "create symbolic link" privilege (Developer Mode / admin),
MSYS2 `ln -s` silently **copies** the directory, which goes stale on the
first edit, and `MSYS=winsymlinks:nativestrict` fails outright.

`tools/lhtest` therefore falls back to an **NTFS directory junction**
(`cmd.exe /c mklink /J`), which both MSYS and native programs follow and which
needs no privilege. If you write similar tooling, do the same:

```sh
MSYS2_ARG_CONV_EXCL='*' cmd.exe /c mklink /J "$(cygpath -w "$dest")" "$(cygpath -w "$src")"
```

`MSYS2_ARG_CONV_EXCL='*'` is required, otherwise MSYS rewrites `/c` into
`C:\` and `cmd` rejects it. Note also that `cmd` alone hits MSYS2's
`/usr/bin/cmd` script — use `cmd.exe`.

### Trap 4: the network goes through a TLS-intercepting proxy

Direct `curl https://...` fails with *"self-signed certificate in certificate
chain"*. lhelper already passes `--insecure`, so its own downloads work.
Separately, `download.savannah.gnu.org` intermittently returns **502** through
this proxy. When that happens, seed the archive cache by hand instead of
fighting it — lhelper does not checksum source archives:

```sh
# mirror -> lhtest archive cache (name must match lhelper's mangled URL name)
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc '
  curl -sSkL --fail -o /tmp/ft.tar.gz \
    "https://downloads.sourceforge.net/project/freetype/freetype2/2.13.3/freetype-2.13.3.tar.gz" &&
  mkdir -p /tmp/lhtest/tree/var/lhelper/archives &&
  cp /tmp/ft.tar.gz /tmp/lhtest/tree/var/lhelper/archives/savannah_gnu_org_freetype_freetype_2.13.3.tar.gz'
```

Keep a stash outside the sandbox (e.g. `/tmp/lh-archive-stash/`): `lhtest -f`
wipes `var/lhelper/archives` along with everything else.

### Trap 5: path lists are `:`-separated — trust the runtime's conversion

Every path list lhelper composes (`PATH`, `PKG_CONFIG_PATH`,
`LD_LIBRARY_PATH`, ...) uses `:` and POSIX paths, on every platform. lhelper
is an MSYS process, so when it spawns a **native** program (cmake, ninja,
pkgconf) the MSYS2 runtime converts path-like values to `;`-separated
Windows paths at that moment; MSYS children (bash, make) read the POSIX form
directly. Do **not** hand-convert separators or paths in the Lua code — a
value the heuristic mishandles is excluded case by case with
`MSYS2_ARG_CONV_EXCL` / `MSYS2_ENV_CONV_EXCL` instead.

The failure mode when this goes wrong is silent and easy to misread: if
pkgconf receives a list it cannot parse it finds nothing, falls back to its
built-in `/mingw64` search path and returns a perfectly plausible answer
from the **system** library. Sanity check after changing anything here:

```sh
tools/lhtest -q sh ". .lhelper/<env>/bin/activate && pkg-config --cflags freetype2"
# must print .lhelper/<env>/include/..., never C:/msys64/mingw64/...
```

To check the *in-process* environment (the one used to build dependent
packages, which is the case that matters), put a throwaway recipe in a copy of
`recipes/` and run it through `lhtest -t <tree>`:

```lua
dependency("freetype2")
print("PROBE=" .. tostring(pkg_config("--cflags", "freetype2")))
```

## Notes for anyone touching `src/lhsys.c` on Windows

There is no Win32 code in `src/lhsys.c` (or anywhere in `src/`): the file is
POSIX-only and a `#error` rejects any compiler that defines `_WIN32`. Keep
it that way — every past Windows-specific branch in there (CreateProcess
command-line quoting, stdout handle sharing modes, read-only attribute
clearing) was a partial reimplementation of something the MSYS2 runtime
already does, and each one carried its own hard-to-diagnose bugs.
