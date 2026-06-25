pushd_quiet () { builtin pushd "$@" > /dev/null; }
popd_quiet  () { builtin popd > /dev/null; }

# Resolve the lhelper-specific Lua interpreter.
# Set once at lhelper startup (LHELPER_LUA_BIN); if missing (standalone
# sourcing of this file, e.g. by create-env.sh), recompute the canonical
# private path from LHELPER_PREFIX. No validity check here -- it was done
# once at lhelper startup; if the binary is gone, lua will simply fail.
_lh_lua () {
    printf '%s' "${LHELPER_LUA_BIN:-$LHELPER_PREFIX/libexec/lhelper/lua}"
}

# Sort option string $1 into canonical form (sorted, space-separated, no
# trailing whitespace) via the options.lua module. Drop-in replacement for
# the former `lh-sort "$1"` invocation minus its trailing space + newline.
opts_canonical () {
    local luabin
    luabin="$(_lh_lua)"
    # Pass the option string via stdin so lua's command-line arg parser does
    # not get confused by tokens starting with "-" (which lua would otherwise
    # try to load as a script file after the -e chunk).
    printf '%s' "$1" | "$luabin" -e 'local o=require("options");print(o.canonical(io.read("*a")))'
}

# Populate the array named by $1 with the option names accepted by the recipe
# at $2 (via Options.from_recipe). Names are normalized to have a leading "-"
# prepended, regardless of whether they were discovered from an
# `availables=(...)` block (bare) or from case-arms (-prefixed).
options_from_recipe () {
    local -n _ofr_out="$1"
    local recipe_file="$2"
    _ofr_out=()
    local luabin
    luabin="$(_lh_lua)"
    # Pass the file path via the LH_FILE env var -- passing it as a positional
    # arg after `-e chunk` would make lua try to load it as a Lua script file.
    local raw
    raw="$(LH_FILE="$recipe_file" "$luabin" -e '
        local o = require("options")
        for _, n in ipairs(o.from_recipe(os.getenv("LH_FILE"))) do
            print(n)
        end' 2>/dev/null)"
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if [[ "$name" == -* ]]; then
            _ofr_out+=("$name")
        else
            _ofr_out+=("-$name")
        fi
    done <<< "$raw"
}

# Transform the variable named by $1 (bash nameref) in place: its content,
# expected to be a download URL, is rewritten into a sanitized archive
# filename. Backed by archive_filename.lua. Drops in for the former bash
# char-loop in build-helper.sh.
transform_to_archive_filename () {
    local -n url="$1"
    local luabin
    luabin="$(_lh_lua)"
    # Pass the URL via stdin so the leading "-" tokens (none in a URL, but in
    # general) cannot confuse lua's arg parser. Matches opts_canonical's
    # invocation shape.
    url="$(printf '%s' "$url" | "$luabin" -e 'local a=require("archive_filename");io.write(a.transform(io.read("*a")))')"
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

