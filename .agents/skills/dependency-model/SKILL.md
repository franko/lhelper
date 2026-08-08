---
name: dependency-model
description: Use when a recipe declares dependency() or provides(), when a package resolves to the system library instead of a recipe (or the reverse), when "options for installed package do not match" or a version mismatch is reported, or when reasoning about the lhelper-packages registry and virtual packages. Covers the spec grammar, matching rules, the resolution passes and how dependencies reach the build digest.
---

# Dependencies, virtual packages and resolution

lhelper resolves dependencies before building anything: every recipe is run
twice, and the first run — the *dependencies phase* — exists only to collect
what the package needs and what it provides. `dependency()` and `provides()`
record their argument in that phase and do nothing in the run phase
(`recipe.lua:405`), which is why they are safe to call unconditionally, from
inside an option branch, anywhere in the recipe.

## The spec grammar

Both functions take a package spec:

```
<name> [-option ...] [<comparator><version>]
```

with comparators `>=`, `<=`, `>`, `<`, `=`. Arguments are concatenated with
spaces, so `dependency("sdl2", "-opengl", ">=2.0.14")` and
`dependency("sdl2 -opengl >=2.0.14")` are the same thing.
`pkg.normalize_spec` sorts the options so that the order a recipe writes them
in never matters.

`dependency("--optional", "<spec>")` records the spec with a `?` prefix.

### provides() takes a bare version — no comparator

```lua
provides("blas 3.12.0")        -- correct
provides("blas = 3.12.0")      -- WRONG: the version is read as "="
```

A *spec* may carry a comparator, but a `provides` line is stored as a registry
*entry*, and `test_package_spec` reads an entry's version as the first word
after the name that is not an option (`pkg.lua:106`). With `= 3.12.0` the
recorded version becomes `=` and every version comparison against it is
nonsense. (Older bash recipes wrote `provides "freetype2 = $version"`; do not
carry that form over.)

## What matching actually checks

`pkg.test_package_spec(spec, entry)` returns 0 on a match, or:

| Code | Meaning |
|---|---|
| 1 | name mismatch |
| 2 | the spec's options are not a subset of the entry's options |
| 3 | version comparison failed |
| 100 | invalid spec (a word that is neither an option nor a comparator+version) |

Codes 2 and 3 are what surface as *"options for installed package X do not
match the required spec"* and *"incompatible version for installed package X"*
(`report_dependency_error`). Note the direction of code 2: an installed package
may have **more** options than required, never fewer. Requiring
`sdl2 -opengl` is satisfied by an installed `sdl2 -opengl -audio`.

Version comparison (`pkg.vercomp`) splits on `.` and compares each component by
its **leading digits only**, missing components counting as 0. So `2.28.5+2`
compares equal to `2.28.5` — the recipe revision is deliberately ignored — and
`1.3` equals `1.3.0`.

## The registry file

`<env-prefix>/bin/lhelper-packages`, one line per installed package:

```
openblas -lapack 0.3.34 a8c4b8e4ab4c1370a6d481587948cc56
blas 3.12.0 : openblas -lapack 0.3.34 a8c4b8e4ab4c1370a6d481587948cc56
lapack 3.12.0 : openblas -lapack 0.3.34 a8c4b8e4ab4c1370a6d481587948cc56
```

The form is `<name> [options] <recipe-version> <digest>`. A line containing
` : ` is a **virtual package**: the left side is what a `provides()` declared,
the right side is the providing package's line. `pkg.resolve_entry` returns the
left side normally and the right side when asked for the `link` — that is how a
dependency on `blas` finds the package that must be installed to satisfy it.

Re-registering a package first drops the old ` : ` lines that point at it, so
reinstalls do not accumulate stale virtual entries (`pkg.register_package`).

## How a dependency is satisfied

`dependency_status` (`install.lua:301`) decides, in this order:

1. **A registry line with that name exists** — test the spec against it. Match
   → done; mismatch → report and exit. Note that a mismatch is fatal, not a
   trigger to install a second copy: an environment holds one version of a
   package.
2. **No registry line** — a system library is used only if the environment
   prefers the system one for this name **or** no recipe provides it at all
   (`installer.latest_package_version(name)` is nil). The system version comes
   from `pkg-config --modversion <name>`, falling back to
   `<name>-config --version`. If it is found but fails the spec, that is fatal.
3. **Otherwise** the dependency is missing and a package is added to the plan
   automatically.

So the default is *recipes win over system libraries*, and the escape hatch is
the spec's `prefer_system_libraries`: `true` (stored as `*`, meaning every
package) or a list of names, kept in the environment's `lhelper-config` as
`LHELPER_PREFER_SYSTEM_LIBRARIES` so that later `install` calls agree with the
original `create`.

**Optional dependencies are never installed automatically.** `resolve` skips
any spec starting with `?` (`install.lua:670`); they only influence the usage
list below, where they resolve to the system version or to `[not-found]`.

## The resolution passes

`resolve_plans_pass` walks the requested packages depth-first, calling each
recipe's dependencies phase, adding a plan for every unsatisfied dependency,
and recording cycles (it exits with the chain `a -> b -> a`).

One case restarts the whole pass: when a package was added automatically with
too few options and another package then requires it with more options, the
options of both are accumulated and the pass is abandoned with
`error({restart = true})`. `resolve_install_plans` retries up to
`RESOLVE_PASSES_LIMIT` (16) times before giving up. This is why an
automatically added package can end up with options nobody asked for
individually — the union of what all its dependents needed.

Explicitly requested packages win: if the spec lists a package, its own
arguments are used rather than the ones synthesized for a dependency.

## Dependencies are part of the digest

`compute_package_list` turns the declared dependencies into *usage lines* — the
actual entry used for each, or `<name>[system] <version>`, or
`<name>[not-found]` — and those lines go into `digest_content` after the
compiler configuration. Consequences worth remembering:

- Rebuilding a dependency with different options changes the dependent
  package's digest, so it is rebuilt too rather than silently relinked.
- Switching a dependency between a recipe and the system library changes the
  digest as well (`[system]` appears in the line).
- `lhelper create --show-dependencies <spec>` prints each package's usage
  lines as it is installed. The flag belongs to `create`/`activate`
  (`main.lua:324`), not to `install`.

To see them for a built package, read the saved digest content:
`cat "$LHELPER_WORKING_DIR/digests/<digest>"`.

## Writing dependencies in a recipe

```lua
-- unconditional
dependency("zlib")

-- tied to an option, still safe in both phases
for _, a in ipairs(options) do
    if a == "-brotli" then
        dependency("brotli")
    end
end

-- optional: used if present, never installed for you
dependency("--optional", "libpng")

-- virtual packages this recipe satisfies
provides("blas " .. netlib_version)
```

The name used in `dependency()` must be the name other recipes and
`pkg-config` know: it is looked up both in the registry and, as a fallback,
with `pkg-config --modversion`. Check `recipes/index` for a recipe of that
name before inventing one.
