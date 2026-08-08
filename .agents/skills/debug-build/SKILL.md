---
name: debug-build
description: Use when an lhelper package build fails, when a recipe change appears to have no effect, or when you need to find the logs, the preserved build tree or the reason two builds produced different digests. Covers the recipe exit codes, where every log lives, the cached-package trap, and how to reproduce a failure cheaply.
---

# Triage a failed lhelper build

The error lhelper prints on the terminal is a summary; the useful output is
always in a log file, and the failed build tree is still on disk. Before
changing a recipe, find out which of the two phases failed and read the log.

## The exit codes

A recipe fails through `util.fail(code, msg)`; the code selects the message
`recipe_error_report` prints (`install.lua:462`) and says where to look:

| Code | Meaning | Where it comes from |
|---|---|---|
| 3 | A required command is missing | `check_commands` / `test_commands` |
| 4 | Interrupted (Ctrl-C during a download) | `download_guarded` |
| 5 | Download error (curl or git clone), or a corrupt/empty archive | `enter_archive`, `enter_git_repository` |
| 6 | Build error — the default for any command run by the recipe | `log_run`, `build_and_install` |
| 7 | Recipe configuration error (bad options, unsupported CPU, ...) | `fail_config` |
| 1 | Everything else: recipe syntax error, unknown build system, a directory that cannot be removed | `util.fail(1, ...)`, `run_recipe` |

Codes 3 and 5–7 dump the recipe's **stderr log** to the terminal, so what you
see is usually already the tail of the real error. Code 1 (and anything
unrecognized) prints only the log file names.

Note that the recipe's own `print()` goes to the *stdout* log, which is never
dumped — when a recipe prints the command it is about to run, that line is in
the stdout log only.

## Where the logs are

Two phases run for every package, each writing its own pair of logs:

| Phase | Directory | File names |
|---|---|---|
| run (the actual build) | `<env-prefix>/logs` | `<pkg>-stdout.log`, `<pkg>-stderr.log` |
| dependencies, from `install` | `<env-prefix>/logs` | `deps-<pkg>-stdout.log`, `deps-<pkg>-stderr.log` |
| dependencies, from `create` | `$LHELPER_TMPDIR` | `deps-<pkg>-stdout.log`, `deps-<pkg>-stderr.log` |

The asymmetry matters: during `create` no environment exists yet, so the
dependency-phase logs land in the temp dir (`install.lua:913`), not next to the
build logs. `LHELPER_TMPDIR` is `$TMPDIR` or `/tmp` (`main.lua:35`) — it is
**not** inside the environment.

Both logs are truncated at the start of each phase, so they always describe the
last attempt only.

## The preserved build tree

The extracted sources live in `$LHELPER_TMPDIR/build/<archive-top-dir>` and are
deliberately **not** cleaned after a build. `clean_build_root` wipes the
directory only at the *start* of the next build (`recipe.lua:336`), precisely so
a failure can be inspected:

```sh
ls "$TMPDIR/build"
cd "$TMPDIR/build/<pkg>-<version>" && cat config.log     # or CMakeFiles/*.log
```

This is where to look when `./configure` fails for a reason the stderr log
summarizes badly.

## The trap: your recipe change did nothing

`execute_install_plan` reuses a previously built package instead of running the
recipe when all of these hold (`install.lua:791`):

- `--rebuild` was not given,
- `--local` was not given,
- the version does not start with `git-`,
- and an archive named `<pkg><options-tag>_<recipe-version>_<digest>.tar.gz`
  exists in `<LHELPER_WORKING_DIR>/packages/<LHELPER_PACKAGE_VERSION>` **or** on
  lhelper.cc.

The recipe file's contents are not part of that name — only its *file name*
(`recipe_version`, including any `+N`) and the build-environment digest are. So
editing a recipe in place and re-running gives you the old binary, with the
reassuring message `Found an existing package`. Either:

```sh
lhelper install --rebuild <pkg>     # ignore saved and remote packages
lhelper install --local <pkg>       # use the local recipe, never reuse remote nor upload
```

`install` refuses to run outside an activated environment (it checks
`LHELPER_ENV_NAME`), so in the sandbox source the activate script first:

```sh
tools/lhtest -q sh '. .lhelper/<env>/bin/activate && lhelper install --rebuild <pkg>'
```

or bump the recipe to `<pkg>_<version>+1.lua` when the change is meant to ship.
Seeing `Found an package in the remote location` during development almost
always means you wanted `--rebuild`.

## Why two builds differ: read the digest

The digest in the package name is the MD5 of a small human-readable block —
compiler, versions, flags, build type, `MACHTYPE`, `CPU_TYPE`, `CPU_TARGET`, OS
release, and the resolved dependency lines (`digest_content`, `install.lua:360`).
Every digest is saved verbatim:

```sh
cat "$LHELPER_WORKING_DIR/digests/<digest>"
diff "$LHELPER_WORKING_DIR/digests/<digest-a>" "$LHELPER_WORKING_DIR/digests/<digest-b>"
```

That diff answers "why is it rebuilding?" and "why did it not reuse the package
I built yesterday?" directly.

## Reproducing cheaply

Use `tools/lhtest`, which fakes `HOME` (so no upload key is ever in scope) and
puts the working dir inside a throwaway sandbox:

```sh
tools/lhtest -f -b create test.lhelper        # rebuild binary, fresh sandbox
tools/lhtest -p p2 create other.lhelper       # a second, independent project
tools/lhtest sh 'ls .lhelper/test/logs'       # inspect inside the sandbox
tools/lhtest -q path                          # print the sandbox location
tools/lhtest reset                            # delete it
```

The sandbox persists between invocations, so a failed build stays inspectable
until the next `--fresh`.

To iterate on one package without redoing the environment, `create` once and
then run `install --rebuild <pkg>` in an activated shell repeatedly: `lua/` and
`recipes/` are symlinked into the sandbox, so recipe edits take effect with no
copy step.

## Machine-specific traps

- **macOS, `C compiler cannot create executables`** with
  `ld64.lld: error: library not found for -lSystem` in `config.log`: an
  `ld64.lld` earlier on `PATH` than Apple's `/usr/bin/ld` (check `which ld`).
  A toolchain problem, not a recipe problem — fix `PATH` or set
  `ldflags = "-fuse-ld=/usr/bin/ld"` in the spec.
- **Downloads failing mid-transfer** (`curl: (92) HTTP/2 stream ... PROTOCOL_ERROR`)
  are network flakes; `enter_archive` already retries five times and removes the
  partial file. Retry before suspecting the URL.
- **MSYS2**: see the `msys2-test-env` skill — a build that fails for lack of
  `gcc`/`make` usually means the command did not reach a MINGW64 login shell.
