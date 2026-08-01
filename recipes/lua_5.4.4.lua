-- Currently the shared and static library are always both compiled
-- and the lua executable is linked to the shared library.

local needs_shared, needs_interp, version_tag_suffix = false, false, ""
local opts = {}
for _, opt in ipairs(options) do
    if opt == "-shared" then
        needs_shared = true
    elseif opt == "-interp" then
        needs_interp = true
    elseif opt == "-utf8" then
        version_tag_suffix = "-utf8"
    else
        opts[#opts + 1] = opt
    end
end

if not needs_shared then
    opts[#opts + 1] = "-Dshared=false"
end
if not needs_interp then
    opts[#opts + 1] = "-Dapp=false"
end

enter_git_repository("https://github.com/franko/lua.git",
    "v" .. version .. version_tag_suffix)
build_and_install("meson", table.unpack(opts))
