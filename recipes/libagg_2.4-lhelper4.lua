check_commands("meson", "ninja", "git")

local opts = {}
local freetype = false
local demos = false

for _, a in ipairs(options) do
    if a == "-freetype" then
        freetype = true
    elseif a == "-demos" then
        demos = true
    else
        opts[#opts + 1] = a
    end
end

if freetype then
    dependency("freetype2")
end

opts[#opts + 1] = "-Dfreetype=" .. (freetype and "enabled" or "disabled")
-- The demo applications are built only on the platforms agg provides its
-- platform support layer for: windows, linux and the BSDs, but not macOS.
opts[#opts + 1] = "-Ddemos=" .. (demos and "true" or "false")

enter_git_repository("https://github.com/franko/agg.git", "v" .. version)

-- FT_Outline.tags is "unsigned char *" in current freetype but the agg
-- freetype font engine declares the local pointer as "char *", which does not
-- compile. The tag values are only read, so widening the local type is enough.
inside_archive_apply_patch("agg-2.4-freetype-outline-tags")
-- agg always auto-detects freetype: add a meson option so the font engine is
-- built when, and only when, the recipe asks for it.
inside_archive_apply_patch("agg-2.4-freetype-meson-option")

build_and_install("meson", table.unpack(opts))
