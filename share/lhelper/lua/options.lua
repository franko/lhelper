-- options.lua - canonical option-string handling for lhelper.
--
-- An "option string" is a space-separated list of tokens like
--   "-shared -pic -prefix=/usr"
-- They identify package variants, drive build configuration, and determine
-- compatibility. This module owns the canonical representation so callers
-- stop reimplementing split / sort / match / dedup in bash.
--
-- Sorting is byte-lexicographic via Lua's default `<` on strings, which
-- matches what the former lh-sort C helper produced (strcmp).

-- Self-locate so require("options") works whether or not LUA_PATH is set,
-- mirroring the bootstrap pattern used by resolver.lua.
pcall(function()
    local script_dir = debug.getinfo(1, "S").source:match("@?(.*/)")
    if script_dir then
        package.path = script_dir .. "?.lua;" .. package.path
    end
end)

local M = {}

-- Split a string on whitespace (one or more spaces) into an array.
-- Returns {} for an empty / whitespace-only string. Token order is preserved.
-- NOTE: this is the simple space-split nuance used by the prior lh-sort callers
-- (each option is a single shell word without embedded spaces; values after
-- "=" are part of the same token, e.g. "-prefix=/usr").
local function split_ws(s)
    local t = {}
    if not s then return t end
    for tok in tostring(s):gmatch("%S+") do
        t[#t + 1] = tok
    end
    return t
end

-- parse: option string -> unsorted array of tokens (preserving order).
-- Whitespace-separated, embedded spaces not supported (matches lh-sort input).
function M.parse(s)
    return split_ws(s)
end

-- tostring: array -> canonical string. Sorts byte-lexicographically (matches
-- the former lh-sort output), joins with single spaces, no trailing space.
-- Empty / nil array -> "".
function M.tostring(t)
    if not t or #t == 0 then return "" end
    local copy = {}
    for i = 1, #t do copy[i] = t[i] end
    table.sort(copy)
    return table.concat(copy, " ")
end

-- canonical: parse then tostring. Equivalent to `lh-sort "$input"` minus the
-- trailing newline/space that the C binary emitted.
function M.canonical(s)
    return M.tostring(M.parse(s))
end

-- contains: exact set membership (NOT substring match).
-- `t` may be an array or a canonical string; `o` is a single option token.
function M.contains(t, o)
    if type(t) == "string" then t = M.parse(t) end
    if not o then return false end
    for i = 1, #t do
        if t[i] == o then return true end
    end
    return false
end

-- subset: are all options of `a` present in `b` (exact-match, order-independent)?
-- Both `a` and `b` may be arrays or strings.
-- Empty `a` is always a subset (matches test_options semantics).
function M.subset(a, b)
    if type(a) == "string" then a = M.parse(a) end
    if type(b) == "string" then b = M.parse(b) end
    local bset = {}
    for i = 1, #b do bset[b[i]] = true end
    for i = 1, #a do
        if not bset[a[i]] then return false end
    end
    return true
end

-- merge: union of `a` and `b`, deduped, canonicalized (sorted, space-joined).
-- Both arguments may be arrays or strings.
function M.merge(a, b)
    if type(a) == "string" then a = M.parse(a) end
    if type(b) == "string" then b = M.parse(b) end
    local seen, out = {}, {}
    local function add(x)
        if not seen[x] then seen[x] = true; out[#out + 1] = x end
    end
    for i = 1, #a do add(a[i]) end
    for i = 1, #b do add(b[i]) end
    return M.tostring(out)
end

-- extract_name: package name from a spec like "name -opts >=ver".
-- Returns the first whitespace token (the bare package name) or nil.
function M.extract_name(spec)
    if not spec then return nil end
    local name = tostring(spec):match("^%s*(%S+)")
    return name
end

-- extract_version: parse a version constraint from "name -opts >=ver" or
-- "name >=ver". Returns {op=">=", ver="1.2.3"} or nil when no constraint.
-- Recognized operators: >=, <=, >, <, =.
function M.extract_version(spec)
    if not spec then return nil end
    -- Lua patterns lack regex alternation `(|)`, so use a character class
    -- `[<>=]` + optional `=?` to recognize the four two-char operators and
    -- the three one-char ones in a single match.
    for tok in tostring(spec):gmatch("%S+") do
        local op, ver = tok:match("^([<>=]=?)([%d%.]+.*)$")
        if op and ver then
            return { op = op, ver = ver }
        end
    end
    return nil
end

-- from_recipe: read a recipe file and enumerate the option names it accepts.
-- Mirrors the existing dual-strategy bash logic in check_command / test_command:
--   1. If a line beginning `availables=(...)` is present, join all such lines,
--      strip backslashes and quotes, then split the captured group on
--      whitespace. Yields the raw names (no leading "-").
--   2. Otherwise, scan for case-arms of the form `^<ws>-name)<ws>$` and
--      collect distinct names (with the leading "-").
-- The two branches use different conventions on the leading "-", replicating
-- the prior bash code's exact output: availables names are returned bare;
-- case-arm names are returned with the leading "-".
-- Returns an ordered array (first-seen order, duplicates removed).
function M.from_recipe(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()

    -- Strategy 1: availables=(...). Find every line that starts (after
    -- whitespace) with `availables=(`. Concatenate them, drop backslashes,
    -- capture between the FIRST `availables=(` and the LAST `)` (matching the
    -- greedy ERE behaviour of the prior `[[ ... =~ availables=\((.*)\) ]]`).
    local avail_lines = {}
    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%s*availables=%(") then
            avail_lines[#avail_lines + 1] = line
        end
    end
    if #avail_lines > 0 then
        local joined = table.concat(avail_lines, " "):gsub("\\", "")
        local inner = joined:match("availables=%((.*)%)")
        if inner then
            local out, seen = {}, {}
            for tok in inner:gmatch("%S+") do
                local clean = tok:gsub('"', "")
                if clean ~= "" and not seen[clean] then
                    seen[clean] = true
                    out[#out + 1] = clean
                end
            end
            if #out > 0 then return out end
        end
    end

    -- Strategy 2: scan case arms `^<ws>-name)<ws>$`. Names returned WITH "-".
    local out, seen = {}, {}
    for line in content:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") then
            local name = line:match("^%s+(-[a-zA-Z][a-zA-Z0-9_-]*)%)[%s]*$")
            if name and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
    end
    return out
end

return M