check_commands("meson", "ninja", getenv("CC"), getenv("CXX"))

if platform == "linux" then
    dependency("x11")
    dependency("xext")
    dependency("--optional", "xrandr")
    dependency("--optional", "xrender")
    dependency("--optional", "xfixes")
    dependency("--optional", "xcursor")
    dependency("--optional", "xi")
end

local opts = {}
local xft_option = "-Dxft=false"
local apps_option = "-Dapps=false"

for _, a in ipairs(options) do
    if a == "-jpeg" then
        opts[#opts + 1] = "-Djpeg=true"
        dependency("libjpeg")
    elseif a == "-opengl" then
        opts[#opts + 1] = "-Dopengl=true"
    elseif a == "-png" then
        opts[#opts + 1] = "-Dpng=true"
        dependency("libpng16")
    elseif a == "-zlib" then
        opts[#opts + 1] = "-Dzlib=true"
        dependency("zlib")
    elseif a == "-bzlib" then
        opts[#opts + 1] = "-Dbzlib=true"
    elseif a == "-xft" then
        xft_option = "-Dxft=true"
        dependency("freetype2")
        dependency("xft")
    elseif a == "-cups" then
        opts[#opts + 1] = "-Dcups=true"
        dependency("cups")
    elseif a == "-apps" then
        apps_option = "-Dapps=true"
    else
        opts[#opts + 1] = a
    end
end

enter_git_repository("https://github.com/franko/fox.git", "v" .. version .. "-lhelper")
build_and_install("meson", xft_option, apps_option, table.unpack(opts))
