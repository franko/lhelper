pushd_quiet () { builtin pushd "$@" > /dev/null; }
popd_quiet  () { builtin popd > /dev/null; }

# Resolve a Lua interpreter for short-lived option-handling invocations.
# Prefers LHELPER_LUA_BIN (set by ensure_lua in the lhelper main script when
# already executed), then the installed binary, the in-tree compiled binary,
# then any system `lua` on PATH. Echoes the path, or empty string if none.
_lh_lua () {
    if [[ -n "${LHELPER_LUA_BIN:-}" && -x "$LHELPER_LUA_BIN" ]]; then
        echo "$LHELPER_LUA_BIN"; return
    fi
    if [[ -n "${LHELPER_PREFIX:-}" && -x "$LHELPER_PREFIX/bin/lua" ]]; then
        echo "$LHELPER_PREFIX/bin/lua"; return
    fi
    if [[ -n "${LHELPER_PREFIX:-}" && -x "$LHELPER_PREFIX/src/lua/src/lua" ]]; then
        echo "$LHELPER_PREFIX/src/lua/src/lua"; return
    fi
    command -v lua 2>/dev/null
}

# Sort option string $1 into canonical form (sorted, space-separated, no
# trailing whitespace) via the options.lua module. Drop-in replacement for
# the former `lh-sort "$1"` invocation minus its trailing space + newline.
opts_canonical () {
    local luabin
    luabin="$(_lh_lua)"
    if [[ -z "$luabin" ]]; then
        # Lua unavailable: fall back to the raw input verbatim. Sorting is
        # lost, but callers still receive a value they can use. lhelper
        # requires Lua for the resolver anyway, so this branch is a soft
        # error path (not a hang).
        printf '%s\n' "$1"
        return 0
    fi
    # Pass the option string via stdin so lua's command-line arg parser does
    # not get confused by tokens starting with "-" (which lua would otherwise
    # try to load as a script file after the -e chunk).
    printf '%s' "$1" | "$luabin" -e 'local o=require("options");print(o.canonical(io.read("*a")))'
}

# Figure out the default library directory.
# Adapted from https://github.com/mesonbuild/meson/blob/master/mesonbuild/mesonlib.py
# Returns one or more paths separated by a colon. It can return multiple values
# because on debian with multiarch there is the lib directory and its multiarch
# subdirectory.
# The first directory will be used by lhelper to install new pkg-config files if
# the build system doesn't do it natively.
default_libdir () {
    local -n libs="$1"
    if [ -f /etc/debian_version ]; then
        local archpath=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
        if [ $? == 0 -a ${archpath:-none} != "none" ]; then
            libs=("lib/$archpath" lib)
            return
        fi
    fi
    if [ -d /usr/lib64 -a ! -L /usr/lib64 ]; then
        libs=(lib64)
        return
    fi
    libs=(lib)
}

