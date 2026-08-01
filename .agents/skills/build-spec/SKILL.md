---
name: build-spec
description: Use when creating or editing an lhelper build specification file (.lhelper). Covers the available variables, the sandbox environment, package list syntax, platform detection, and how to test a spec file.
---

# Craft an lhelper build specification (.lhelper) file

A `.lhelper` file is a Lua script that declares the compiler toolchain,
compiler/linker flags, CPU target, build type, system-library preference, and
the list of packages for an lhelper *environment*. lhelper reads this file
when you run `lhelper create <name>` or `lhelper activate <name>`.

## Where spec files live

Spec files can be placed anywhere. The convention is `<name>.lhelper`. When
you run `lhelper create myproject`, lhelper looks for `myproject.lhelper` in
the current directory; if it doesn't exist, it generates a commented template
(with `-e` it also opens an editor). The environment's working data
(built packages, logs, digest) lives in a `.lhelper/` directory next to the
spec file.

Use the model: `build.lhelper` at the repo root as the live example.

## The sandbox

The spec file runs in a restricted sandbox (`lua/main.lua:202`). The only
globals available are:

| Global      | Value                                              |
|-------------|----------------------------------------------------|
| `getenv`    | `os.getenv` — read an environment variable         |
| `os`        | the Lua `os` table (for `os.execute`, etc.)        |
| `string`    | the Lua `string` table                             |
| `platform`  | `"darwin"`, `"linux"`, or `"windows"`              |

There is no `io`, no `require`, no `lhsys`, and no recipe API. The file is
purely declarative — set the variables described below and lhelper reads them
after the chunk runs.

No shebang or `#!/bin/bash` line is needed; the file is plain Lua.

## Supported variables

The spec file sets these variables as globals (lowercase). All are optional
except `packages`.

| Variable                  | Default       | Description |
|---------------------------|---------------|-------------|
| `cc`                      | `"gcc"`       | C compiler (may include options, e.g. `"ccache gcc"`) |
| `cxx`                     | `"g++"`       | C++ compiler |
| `cflags`                  | `""`          | Extra C compiler flags (optimization/debug flags are added automatically) |
| `cxxflags`                | `""`          | Extra C++ compiler flags |
| `ldflags`                 | `""`          | Extra linker flags |
| `cpu_type`                | auto-guessed  | CPU architecture type, e.g. `"x86-64"`, `"arm64"` |
| `cpu_target`              | auto-guessed  | Specific CPU target, e.g. `"nehalem"`, `"armv8"` |
| `build_type`              | `"Release"`   | Must be `"Release"` or `"Debug"` |
| `prefer_system_libraries` | nil           | `true` (all), a list `{ "zlib", "openssl" }`, or a space-separated string `"zlib openssl"` |
| `packages`                | `{}` (required) | List of package spec strings (see below) |

Only set `cpu_type` / `cpu_target` if you need to cross-compile or force a
specific microarchitecture. When omitted, lhelper guesses from the host system.

## The `packages` list

Each entry is a string with the format:

```
"<name> [options] [version]"
```

- **name**: the package name matching a recipe in `recipes/` or the index.
- **options**: space-separated words starting with `-`, e.g. `-threads -opengl`.
  Options are sorted alphabetically by the resolver; order in the spec string
  doesn't matter.
- **version**: an optional version string (first non-option, non-`-prefix=`
  word). When given, lhelper resolves that exact version instead of the latest
  from `recipes/index`. Use this to pin a specific upstream release.

Examples:

```lua
packages = {
    "freetype2",                             -- latest version, no options
    "sdl2 -threads -opengl",                 -- latest, with options
    "sdl2 2.26.5 -threads -opengl -render",  -- pinned version, with options
    "lua -utf8",                             -- options are forwarded to the recipe
}
```

Options refine what the *recipe* builds. For example `sdl2 -x11` enables the
X11 video backend (the recipe declares `dependency("x11")` when it sees
`-x11`). Options are defined by each recipe; look at the recipe source to
know which ones are available.

## Dependencies are resolved automatically

You only need to list the libraries your project *directly* uses. lhelper
reads each recipe's `dependency()` calls and installs the transitive closure.
For example, if you list only `"freetype2"`, lhelper will also install `pcre2`
if the freetype2 recipe depends on it.

List a dependency explicitly only when you need to choose its options or pin
its version:

```lua
packages = {
    "freetype2",
    "sdl2 -opengl",      -- need sdl2 with OpenGL support
    "lua",               -- lua is pulled in by another dep, but listed to
                         -- prevent the system lua from being used
}
```

## Platform detection

Use the `platform` variable to switch package lists per OS. The value is one
of `"darwin"`, `"linux"`, or `"windows"` (set at build time in `src/lhsys.c`,
exposed via `util.platform`).

```lua
if platform == "windows" then
    packages = { "pcre2", "freetype2", "sdl2 -threads -loadso", "lua -utf8" }
elseif platform == "linux" then
    packages = { "pcre2", "freetype2", "sdl2 -x11 -threads -loadso", "lua" }
else
    -- darwin
    packages = { "pcre2", "freetype2", "sdl2 -threads -opengl -render -loadso", "lua" }
end
```

FreeBSD falls under `"linux"` at the C level (the `#else` branch in
`lhsys.c:434`), which matches the typical bash pattern of treating `freebsd*`
like `linux*` for package selection.

## Using `getenv` for overridable defaults

A common pattern is to let environment variables override the compiler and
build type:

```lua
cc = getenv("CC") or "gcc"
cxx = getenv("CXX") or "g++"
build_type = getenv("BUILD_TYPE") or "Release"
```

`getenv` is `os.getenv` — it returns nil when the variable is unset.

## Preferring system libraries

By default, lhelper builds every dependency from its recipes. Set
`prefer_system_libraries` to use system-provided libraries instead:

```lua
prefer_system_libraries = true                       -- prefer all system libs
prefer_system_libraries = { "zlib", "openssl" }      -- prefer specific ones
prefer_system_libraries = "zlib openssl"             -- same, string form
```

A dependency is taken from the system only when no recipe provides it, unless
`prefer_system_libraries` lists it (or is `true` for all). The preference is
stored in the environment's config as `LHELPER_PREFER_SYSTEM_LIBRARIES`.

## Testing a spec file

Always use `tools/lhtest` (see AGENTS.md): it fakes `HOME` so the real upload
key is never in scope, and symlinks the source tree into a sandbox.

```sh
sh build.sh                                    # rebuild (fast, a few seconds)

# Test spec parsing and dependency resolution (--show-dependencies avoids
# building, but still resolves the full dependency tree)
tools/lhtest create test --show-dependencies

# Full end-to-end test with a one-off spec
tools/lhtest -f create test --packages freetype2 sdl2

# Inspect the resulting environment
tools/lhtest sh 'cat test.lhelper/activate'
tools/lhtest env
```

A spec loading error (syntax, unknown variable) will print immediately.
A successful load followed by `error: no recipe found for "X" version Y`
means the spec is valid but a pinned version has no matching recipe file.

## Template generation

Run `lhelper create -e <name>` to generate a fully commented template and open
it in your editor. The template lists every supported variable with
explanations and commented-out examples. Use this as a starting point.

## Common patterns

**Minimal spec** — just gcc/g++ and a package list:
```lua
cc = "gcc"
cxx = "g++"
build_type = "Release"
packages = { "fmt" }
```

**Cross-platform** — switch packages per OS:
```lua
cc = getenv("CC") or "gcc"
cxx = getenv("CXX") or "g++"
build_type = getenv("BUILD_TYPE") or "Release"

if platform == "linux" then
    packages = { "freetype2", "sdl2 -x11" }
elseif platform == "darwin" then
    packages = { "freetype2", "sdl2 -opengl -render" }
end
```

**Pinning versions** — lock specific upstream releases:
```lua
packages = {
    "freetype2",
    "sdl2 2.28.5 -threads -opengl",
    "lua 5.4.4",
}
```
