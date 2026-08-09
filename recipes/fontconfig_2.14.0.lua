check_commands("meson", "ninja", getenv("CC"))

dependency("freetype2")
dependency("expat")

local util = require "util"

local enable_tools = "disabled"
local private_config = false
local opts = {"-Ddoc=disabled", "-Dnls=disabled", "-Dtests=disabled",
    "-Dcache-build=disabled"}

for _, a in ipairs(options) do
    if a == "-tools" then
        enable_tools = "enabled"
    elseif a == "-private-config" then
        private_config = true
    else
        opts[#opts + 1] = a
    end
end

opts[#opts + 1] = "-Dtools=" .. enable_tools

enter_archive("https://www.freedesktop.org/software/fontconfig/release/fontconfig-" ..
    version .. ".tar.gz")
build_and_install("meson", table.unpack(opts))

if not private_config then
    -- fontconfig's meson build installs the share and etc directories,
    -- which are only useful when a private configuration is requested.
    -- INSTALL_PREFIX is only set in the "run" phase.
    local prefix_dir = getenv("INSTALL_PREFIX")
    if prefix_dir then
        print("Removing fontconfig's share and etc directories")
        util.rm_rf(prefix_dir .. "/share")
        util.rm_rf(prefix_dir .. "/etc")
    end
end
