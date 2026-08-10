dependency("zlib")

local cpu_ext_availables = { "intel-sse", "arm-neon", "mips-msa", "mips-mmi",
    "powerpc-vsx", "loongarch-lsx" }
local cpu_ext_enables = {}

local is_x86_arch = cpu_type:sub(1, 3) == "x86"
if (is_x86_arch and (cpu_target == "i586" or cpu_target == "i686"
    or cpu_target == "pentium2" or cpu_target == "pentium3"))
    or cpu_type == "arm" then
    -- no CPU extensions
elseif is_x86_arch then
    cpu_ext_enables[#cpu_ext_enables + 1] = "intel-sse"
elseif cpu_type == "arm64" then
    cpu_ext_enables[#cpu_ext_enables + 1] = "arm-neon"
elseif cpu_type == "mips" then
    cpu_ext_enables[#cpu_ext_enables + 1] = "mips-msa"
    cpu_ext_enables[#cpu_ext_enables + 1] = "mips-mmi"
elseif cpu_type == "powerpc" then
    cpu_ext_enables[#cpu_ext_enables + 1] = "powerpc-vsx"
elseif cpu_type == "loongarch" then
    cpu_ext_enables[#cpu_ext_enables + 1] = "loongarch-lsx"
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local opts = {}
for _, a in ipairs(options) do
    opts[#opts + 1] = a
end

for _, name in ipairs(cpu_ext_availables) do
    if contains(cpu_ext_enables, name) then
        opts[#opts + 1] = "--enable-" .. name .. "=yes"
    else
        opts[#opts + 1] = "--enable-" .. name .. "=no"
    end
end

-- KNOWN PROBLEM on Windows: configure fails to find zlib installed via
-- lhelper because it doesn't use pkg-config to locate it.
if platform == "windows" then
    local z_cflags = pkg_config("--cflags", "zlib")
    if z_cflags then
        setenv("CC", getenv("CC") .. " " .. z_cflags)
        setenv("CXX", getenv("CXX") .. " " .. z_cflags)
    end
    local z_libs = pkg_config("--libs", "zlib")
    if z_libs then
        local ldflags = getenv("LDFLAGS") or ""
        for opt in z_libs:gmatch("%S+") do
            if opt:sub(1, 2) == "-L" then
                ldflags = ldflags .. " " .. opt
            end
        end
        setenv("LDFLAGS", ldflags)
    end
end

enter_git_repository("https://github.com/pnggroup/libpng", "v" .. version)
build_and_install("configure", table.unpack(opts))
