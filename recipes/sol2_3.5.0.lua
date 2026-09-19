-- sol2 is a header-only library with no build system: single/single.py
-- generates the single-header form, which is then installed by hand
-- together with a generated pkg-config file.

check_commands("python3", "git")

local util = require "util"

enter_git_repository("https://github.com/ThePhD/sol2.git", "v" .. version)

run({"python3", "single/single.py"})

-- INSTALL_PREFIX is only set in the "run" phase; the dependencies phase
-- only evaluates the arguments of the no-op run() calls.
local destdir = getenv("INSTALL_PREFIX") or ""
if destdir ~= "" then
    local include_dir = destdir .. "/include/sol"
    util.mkdir_p(include_dir)
    for _, name in ipairs({"sol.hpp", "config.hpp", "forward.hpp"}) do
        run({"cp", "single/include/sol/" .. name, include_dir})
    end
end

local prefix = getenv("LHELPER_SYSTEM_PREFIX")
local pc = io.open("sol2.pc", "w")
pc:write(
    "prefix=" .. prefix .. "\n" ..
    "includedir=${prefix}/include\n" ..
    "\n" ..
    "Name: sol2\n" ..
    "Description: Sol2 C++ to Lua API wrapper\n" ..
    "URL: https://github.com/ThePhD/sol2\n" ..
    "Version: " .. version .. "\n" ..
    "Cflags: -I${includedir}\n")
pc:close()

install_pkgconfig_file("sol2.pc")
