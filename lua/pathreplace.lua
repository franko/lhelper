-- Replace all the occurrences of an absolute path with a replacement text
-- within a file. Port of the lh-path-replace C helper.
--
-- If the absolute path begins with a drive letter like "C:" all the
-- occurrences of the given path are replaced whether they begin by "c:/",
-- "C:/" or "/c/". In addition, on MSYS, the LH_MSYSROOT environment variable
-- is used to recognize the MSYS root windows path (like C:/msys64/) and
-- treat it as if it were the unix "/".

local util = require "util"

local pathreplace = {}

local MAX_BYTES_BINARY_CHECK = 1024

local function char_is_alphanum_dash(c)
    return c ~= nil and c:match("[%w_%-]") ~= nil
end

local function is_binary(content)
    local head = content:sub(1, MAX_BYTES_BINARY_CHECK)
    return head:find("\0", 1, true) ~= nil
end

-- Replace the occurrences of any of the patterns when the character following
-- the match is not alphanumeric, "-" or "_".
local function replace_patterns(content, patterns, replacement)
    local result = {}
    local pos = 1
    local len = #content
    while pos <= len do
        -- find the earliest match among the patterns
        local best_start, best_end = nil, nil
        for _, pattern in ipairs(patterns) do
            local s = content:find(pattern, pos, true)
            while s do
                local e = s + #pattern - 1
                if not char_is_alphanum_dash(content:sub(e + 1, e + 1)) then
                    if not best_start or s < best_start then
                        best_start, best_end = s, e
                    end
                    break
                end
                s = content:find(pattern, s + 1, true)
            end
        end
        if not best_start then break end
        result[#result + 1] = content:sub(pos, best_start - 1)
        result[#result + 1] = replacement
        pos = best_end + 1
    end
    result[#result + 1] = content:sub(pos)
    return table.concat(result)
end

-- Check if any of the patterns occur in the content (with the same boundary
-- rule used for replacement).
local function find_any(content, patterns)
    for _, pattern in ipairs(patterns) do
        local s = content:find(pattern, 1, true)
        while s do
            local e = s + #pattern - 1
            if not char_is_alphanum_dash(content:sub(e + 1, e + 1)) then
                return true
            end
            s = content:find(pattern, s + 1, true)
        end
    end
    return false
end

-- Compute the list of patterns equivalent to the given absolute path prefix.
local function pattern_variants(pattern)
    local drive = pattern:match("^(%a):/")
    local patterns = {}
    if drive then
        local rest = pattern:sub(3) -- keeps the leading "/"
        patterns[#patterns + 1] = drive:lower() .. ":" .. rest
        patterns[#patterns + 1] = drive:upper() .. ":" .. rest
        patterns[#patterns + 1] = "/" .. drive:lower() .. rest
        local msysroot = os.getenv("LH_MSYSROOT")
        if msysroot and msysroot ~= "" and util.starts_with(pattern, msysroot) then
            local msys_pattern = pattern:sub(#msysroot + 1)
            if pattern:sub(#msysroot, #msysroot) == "/" then
                msys_pattern = pattern:sub(#msysroot)
            end
            patterns[#patterns + 1] = msys_pattern
        end
    else
        patterns[#patterns + 1] = pattern
    end
    return patterns
end

-- Replace in the given file the path prefix "pattern" with "replacement".
-- Returns true on success; returns false when the file is binary and
-- contains the prefix (the caller should emit a warning in this case).
function pathreplace.replace(filename, pattern, replacement)
    local content = util.read_file(filename)
    if not content then return false end
    local patterns = pattern_variants(pattern)
    if is_binary(content) then
        -- Cannot patch a binary file: report an error only if the prefix
        -- actually appears inside the file.
        return not find_any(content, patterns)
    end
    local new_content = replace_patterns(content, patterns, replacement)
    if new_content ~= content then
        util.write_file(filename, new_content)
    end
    return true
end

return pathreplace
