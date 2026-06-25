-- archive_filename.lua - URL-to-archive-filename transformation for lhelper.
--
-- A recipe's enter_archive() is given a download URL; lhelper caches the
-- downloaded archive under a sanitized filename derived from the URL. The
-- original implementation walked the URL character-by-character in bash
-- (~45 lines). The transformation is pure string arithmetic and is moved
-- here verbatim so behavior matches the bash version exactly.
--
-- The algorithm (preserved step for step, including quirks):
--   1. Strip up to and including the first "://" (no-op if absent)
--   2. Split at the last "/" into base_url / file_name
--      (if no "/", bash leaves both equal to the whole string -- preserved)
--   3. base_url: replace every non-alnum char with "_" (dot included)
--   4. file_name: replace every non-alnum/non-dot char with "_"
--   5. Join as "<sanitized_base>_<sanitized_file>"
--   6. Strip uninformative substrings (global, in order):
--        www_, downloads_, download_, _archive_refs_tags_->_,
--        _releases_->_, _release_->_

-- Self-locate so require("archive_filename") works whether or not LUA_PATH
-- is set, mirroring the bootstrap pattern used by options.lua / resolver.lua.
pcall(function()
    local script_dir = debug.getinfo(1, "S").source:match("@?(.*/)")
    if script_dir then
        package.path = script_dir .. "?.lua;" .. package.path
    end
end)

local M = {}

-- Replace every character of s that is NOT in keep-class with "_".
-- keep-class is a Lua pattern character-class fragment WITHOUT the leading
-- "[^" / trailing "]" (we supply those here). Returns the sanitized string.
local function sanitize(s, keep_class)
    return (s:gsub("[^" .. keep_class .. "]", "_"))
end

-- transform: download URL -> sanitized archive filename.
-- Pure function, deterministic. Matches the prior bash char-loop including
-- its no-slash edge case (base and file both become the whole string).
function M.transform(url)
    url = url or ""

    -- 1. Strip up to and including the first "://"
    local clean = (url:gsub("^.-://", ""))

    -- 2. Split at last "/". Pattern anchors: .* is greedy so the last "/"
    --    is the boundary. If the string has no "/", match returns nil and we
    --    fall back to the bash behavior of base == file == clean.
    local base, file
    local b, f = clean:match("^(.*)/([^/]*)$")
    if b then
        base, file = b, f
    else
        base, file = clean, clean
    end

    -- 3 & 4. Sanitize base (alnum only) and file (alnum + ".")
    local base_sane  = sanitize(base,  "%w")
    local file_sane  = sanitize(file,  "%w%.")

    -- 5. Join with "_"
    local result = base_sane .. "_" .. file_sane

    -- 6. Strip uninformative substrings, in the exact order the bash used
    --    (substring replace is global; order matters because some patterns
    --    are prefixes of others, e.g. "download_" is a prefix of
    --    "downloads_").
    result = result:gsub("www_", "")
    result = result:gsub("downloads_", "")
    result = result:gsub("download_", "")
    result = result:gsub("_archive_refs_tags_", "_")
    result = result:gsub("_releases_", "_")
    result = result:gsub("_release_", "_")

    return result
end

return M