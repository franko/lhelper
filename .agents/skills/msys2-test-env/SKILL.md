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

## Build

```sh
MSYSTEM=MINGW64 /c/msys64/usr/bin/bash.exe -lc 'cd /home/AbbateF/dev/lhelper && sh build.sh'
```
Produces `build/lhelper.exe` (a native mingw64 binary, not an MSYS one).

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

### Trap 1: the build root is `C:\Windows\Temp\build` and is shared

`lua/main.lua` hardcodes `LHELPER_TMPDIR = "C:/Windows/Temp"` on Windows, so
every sandbox and every project shares `C:\Windows\Temp\build`. It is wiped at
the *start* of each build (`clean_build_root` in `lua/recipe.lua`) and left in
place afterwards, so after a failure you can go and inspect the source tree
there — but only until the next build starts.

Deleting files there must keep working; if it ever stops, you now get an
explicit `error: cannot remove "..."` instead of a build that silently runs in
a half-deleted tree. Historically the failure surfaced as a baffling
`bash: ./configure: No such file or directory` — see Trap 2.

### Trap 2: Windows refuses to delete read-only files

`DeleteFile` fails on any file carrying the read-only attribute, and build
systems produce those routinely (freetype generates
`builds/unix/freetype2.pc` with mode `0444`). Plain `os.remove` therefore
cannot clean a build tree.

`util.rm_rf` uses `lhsys.remove`, which clears `FILE_ATTRIBUTE_READONLY` and
retries; `lhsys.rmdir` does the same for directories. **Never go back to
`os.remove` in code that deletes build output.** Note that MSYS2's `rm -rf`
does clear the attribute, so a manual `rm -rf` succeeding proves nothing about
the Lua side.

### Trap 3: `ln -s` makes deep copies

Without the Windows "create symbolic link" privilege (Developer Mode / admin),
MSYS2 `ln -s` silently **copies** the directory. `MSYS=winsymlinks:nativestrict`
fails outright here, and `MSYS=winsymlinks:lnk` produces `.lnk` shortcuts that
`lhelper.exe` (a *native* Windows program) cannot follow.

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

### Trap 5: path *lists* need `;` on Windows, but `PATH` does not

MSYS2 auto-translates a `:`-separated list of **POSIX** paths into a
`;`-separated list of **Windows** paths when it hands the environment to a
native program — but only if the value still looks POSIX, and only if the
parent is an MSYS process. Neither holds for lhelper: it is a native binary
that emits `C:/…` paths and spawns `cmake`, `meson` and `pkg-config` directly
via `CreateProcess`. So on Windows those lists must already be `;`-joined.

`lua/env.lua` therefore sets a per-variable separator (`sep`), not a global
one:

| variable | separator | why |
|---|---|---|
| `PATH` | `:` | parsed by bash |
| `LD_LIBRARY_PATH` | `:` | ignored by Windows anyway |
| `PKG_CONFIG_PATH` | `;` on Windows | read by native pkgconf |
| `CMAKE_PREFIX_PATH` | `;` on Windows | read by native cmake (single value today) |

Do **not** "simplify" this back to one separator, in either direction.

The old failure mode was silent and easy to misread: with `:` the env entry
got glued to the next one, pkgconf found nothing, fell back to its built-in
`/mingw64` search path and returned a perfectly plausible answer from the
**system** library. Sanity check after changing anything here:

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

Two Win32 details in there were expensive to find; do not undo them.

**`l_spawn` redirection.** The child's stdout/stderr go to log files that the
Lua side keeps open with `io.open(..., "a")`. The `CreateFileA` share mode
must include `FILE_SHARE_WRITE`, and a failed `CreateFileA` must be
normalised to `NULL` — `INVALID_HANDLE_VALUE` is `(HANDLE)-1`, i.e. *truthy*,
so passing it in `STARTUPINFO.hStdOutput` gives the child a broken stdout.
The symptom is brutal to diagnose: every child exits non-zero (bash → 2) and
**all log files stay empty**.

**`win_clear_readonly`.** `l_remove` and `l_rmdir` drop
`FILE_ATTRIBUTE_READONLY` and retry once. See Trap 2.
