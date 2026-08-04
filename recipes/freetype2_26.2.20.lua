check_commands("make", getenv("CC"))

local with_list = {"zlib", "bzip2", "png", "harfbuzz", "brotli", "librsvg"}
local with_in = {}
local opts = {}

for _, a in ipairs(options) do
    if a == "-brotli" then
        with_in[#with_in + 1] = "brotli"
        dependency("brotli")
    elseif a == "-librsvg" then
        with_in[#with_in + 1] = "librsvg"
        -- This library is provided by GNOME and is based on Cairo
        dependency("librsvg-2.0")
    else
        opts[#opts + 1] = a
    end
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

for _, name in ipairs(with_in) do
    opts[#opts + 1] = "--with-" .. name .. "=yes"
end
for _, name in ipairs(with_list) do
    if not contains(with_in, name) then
        opts[#opts + 1] = "--with-" .. name .. "=no"
    end
end

-- Version from:
-- https://github.com/freetype/freetype/blob/master/docs/VERSIONS.TXT
-- We look up the release number because the recipe version is the libtool
-- version. Columns: release, libtool version, so version.
local version_table = [[
     2.13.3     26.2.20   6.20.2
     2.13.2     26.1.20   6.20.1
     2.13.1     26.0.20   6.20.0
     2.13.0     25.0.19   6.19.0
     2.12.1     24.3.18   6.18.3
     2.12.0     24.2.18   6.18.2
     2.11.1     24.1.18   6.18.1
     2.11.0     24.0.18   6.18.0
     2.10.4     23.4.17   6.17.4
     2.10.3     23.3.17   6.17.3
     2.10.2     23.2.17   6.17.2
     2.10.1     23.1.17   6.17.1
     2.10.0     23.0.17   6.17.0
     2.9.1      22.1.16   6.16.1
     2.9.0      22.0.16   6.16.0
     2.8.1      21.0.15   6.15.0
     2.8.0      20.0.14   6.14.0
     2.7.1      19.0.13   6.13.0
     2.7.0      18.6.12   6.12.6
     2.6.5      18.5.12   6.12.5
     2.6.4      18.4.12   6.12.4
     2.6.3      18.3.12   6.12.3
     2.6.2      18.2.12   6.12.2
     2.6.1      18.1.12   6.12.1
     2.6.0      18.0.12   6.12.0
     2.5.5      17.4.11   6.11.4
     2.5.4      17.3.11   6.11.3
     2.5.3      17.2.11   6.11.2
     2.5.2      17.1.11   6.11.1
     2.5.1      17.0.11   6.11.0
     2.5.0      16.2.10   6.10.2
]]

local release_ver
for release, libtool_ver in version_table:gmatch("(%S+)%s+(%S+)%s+%S+") do
    if libtool_ver == version then
        release_ver = release
        break
    end
end

if not release_ver then
    fail_config("error: unknown release number for freetype2: " .. version)
end

enter_archive("https://download.savannah.gnu.org/releases/freetype/freetype-" ..
    release_ver .. ".tar.gz")
build_and_install("configure", table.unpack(opts))
