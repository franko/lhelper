check_commands("cmake", "ninja", "git")

enter_git_repository("https://github.com/USCiLab/cereal.git", "v" .. version)

local opts = {}
for _, a in ipairs(options) do opts[#opts + 1] = a end
opts[#opts + 1] = "-DJUST_INSTALL_CEREAL=ON"
build_and_install("cmake", table.unpack(opts))

-- cereal is header-only: generate and install a pkg-config file.
local prefix = getenv("LHELPER_SYSTEM_PREFIX")
local pc = io.open("cereal.pc", "w")
pc:write(
    "Name: cereal\n" ..
    "Description: cereal is a header-only C++11 serialization library\n" ..
    "URL: https://uscilab.github.io/cereal/\n" ..
    "Version: " .. version .. "\n" ..
    "Cflags: -I" .. prefix .. "/include\n")
pc:close()

install_pkgconfig_file("cereal.pc")
