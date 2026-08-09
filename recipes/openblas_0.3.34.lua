-- OpenBLAS is built with a plain Makefile: every build choice is a make
-- variable and there is no configure step, so the build and install commands
-- are issued directly with run(). OpenBLAS parallelizes its own build (its
-- getarch adds "MAKEFLAGS += -j <cores>"), so no -j option is passed here.
--
-- Recipe options:
--   -lapack         also build the netlib LAPACK/LAPACKE interface. It is
--                   Fortran code and requires gfortran.
--   -target=<cpu>   force the OpenBLAS TARGET microarchitecture, using the
--                   names of TargetList.txt.
--   -arch=dynamic   include every kernel in the library and select the best
--                   one at run time. This is the default and it gives a much
--                   larger library. -arch=static builds the kernels of the
--                   target CPU only.
--   -threads=false  disable multi-threading (enabled by default).
--
-- Other make variables of interest: DEBUG=1 for a debug build. The available
-- make targets are libs, netlib, shared and tests.

check_commands("make", getenv("CC"))

local util = require "util"

-- Version of the netlib BLAS / LAPACK reference implementation bundled with
-- this OpenBLAS release, from lapack-netlib/CMakeLists.txt.
local netlib_version = "3.12.0"

provides("blas " .. netlib_version)

-- Mapping between lhelper's CPU_TYPE / CPU_TARGET and the OpenBLAS TARGET.
-- The OpenBLAS names are the ones of TargetList.txt; when OpenBLAS has no
-- kernels for a microarchitecture the closest supported one is used, like
-- OpenBLAS itself does when it detects the CPU.
local cpu_table = [[
    x86    pentium2       P2
    x86    pentium3       P2
    x86    pentium4       NORTHWOOD
    x86    prescott       PRESCOTT
    x86    core2          CORE2
    x86    nehalem        NEHALEM
    x86    haswell        HASWELL
    x86-64 x86-64         PRESCOTT
    x86-64 core2          CORE2
    x86-64 athlon         ATHLON
    x86-64 opteron        OPTERON
    x86-64 barcelona      BARCELONA
    x86-64 bobcat         BOBCAT
    x86-64 jaguar         BOBCAT
    x86-64 bulldozer      BULLDOZER
    x86-64 piledriver     PILEDRIVER
    x86-64 steamroller    STEAMROLLER
    x86-64 excavator      EXCAVATOR
    x86-64 zen            ZEN
    x86-64 zen2           ZEN
    x86-64 zen3           ZEN
    x86-64 zen4           ZEN
    x86-64 x86-64-v2      NEHALEM
    x86-64 nehalem        NEHALEM
    x86-64 westmere       NEHALEM
    x86-64 sandybridge    SANDYBRIDGE
    x86-64 x86-64-v3      HASWELL
    x86-64 haswell        HASWELL
    x86-64 broadwell      HASWELL
    x86-64 skylake        HASWELL
    x86-64 alderlake      HASWELL
    x86-64 atom           ATOM
    x86-64 cooperlake     COOPERLAKE
    x86-64 x86-64-v4      SKYLAKEX
    x86-64 skylakex       SKYLAKEX
    x86-64 icelake        SKYLAKEX
    x86-64 tigerlake      SKYLAKEX
    x86-64 sapphirerapids SAPPHIRERAPIDS
    arm    armv6          ARMV6
    arm    armv6+fp       ARMV6
    arm    armv7          ARMV7
    arm    armv7a         ARMV7
    arm    armv7a+fp      ARMV7
    arm    cortexa9       CORTEXA9
    arm    cortexa15      CORTEXA15
    arm64  armv8          ARMV8
    arm64  armv8.2        ARMV8
    arm64  armv8.3        ARMV8
    arm64  armv8.4        ARMV8
    arm64  armv9          ARMV8
    arm64  cortexa53      CORTEXA53
    arm64  cortexa57      CORTEXA57
    arm64  cortexa72      CORTEXA72
    arm64  cortexa73      CORTEXA73
    arm64  cortexa76      CORTEXA76
    arm64  cortexa78      CORTEXA76
    arm64  cortexX1       CORTEXX1
    arm64  neoversen1     NEOVERSEN1
    arm64  neoversen2     NEOVERSEN2
    arm64  neoversev1     NEOVERSEV1
]]

local cpu_arch
for type_name, target_name, openblas_target in cpu_table:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
    if type_name == cpu_type and target_name == cpu_target then
        cpu_arch = openblas_target
        break
    end
end

local dynamic_arch = "1"
local thread_options = {"USE_THREAD=1", "NUM_THREADS=32"}
local use_threads = true
local use_shared = false
local use_lapack = false
local targets = {"libs"}
local opts = {}

for _, a in ipairs(options) do
    local target_opt = a:match("^%-target=(.*)$")
    local arch_opt = a:match("^%-arch=(.*)$")
    local threads_opt = a:match("^%-threads=(.*)$")
    if a == "-lapack" then
        check_commands("gfortran")
        targets[#targets + 1] = "netlib"
        use_lapack = true
        provides("lapack " .. netlib_version)
    elseif target_opt then
        -- The target chooses the CPU microarchitecture. With DYNAMIC_ARCH it
        -- still applies and indicates the older architecture to support.
        cpu_arch = target_opt:upper()
    elseif arch_opt then
        if arch_opt == "dynamic" then
            dynamic_arch = "1"
        elseif arch_opt == "static" then
            dynamic_arch = "0"
        else
            fail_config("error: invalid -arch option: " .. arch_opt)
        end
    elseif threads_opt then
        if threads_opt == "false" then
            thread_options = {"USE_THREAD=0"}
            use_threads = false
        end
    elseif a == "-shared" then
        use_shared = true
    elseif a == "-pic" then
        opts[#opts + 1] = "NEED_PIC=1"
    else
        fail_config("error: unknown option \"" .. a .. "\" in package recipe")
    end
end

if not cpu_arch then
    fail_config("error: unknown CPU_TARGET value for OpenBLAS: " ..
        tostring(cpu_target) .. "/" .. tostring(cpu_type))
end

if not use_lapack then
    opts[#opts + 1] = "NO_LAPACK=1"
end

if use_shared then
    opts[#opts + 1] = "NO_STATIC=1"
    targets[#targets + 1] = "shared"
else
    opts[#opts + 1] = "NO_SHARED=1"
end

local binary = (cpu_type == "x86" or cpu_type == "arm") and "32" or "64"
local prefix = getenv("LHELPER_SYSTEM_PREFIX")
-- INSTALL_PREFIX is only set in the "run" phase; the dependencies phase just
-- evaluates the arguments of the no-op run() calls.
local destdir = getenv("INSTALL_PREFIX") or ""

util.append_all(opts, thread_options)
util.append_all(opts, {"BINARY=" .. binary, "DYNAMIC_ARCH=" .. dynamic_arch,
    "TARGET=" .. cpu_arch, "PREFIX=" .. prefix})

enter_archive("https://github.com/OpenMathLib/OpenBLAS/releases/download/v" ..
    version .. "/OpenBLAS-" .. version .. ".tar.gz")

-- Problem reported when installed as a static library only: the library
-- requires the pthread library to link but "pkg-config --libs" does not
-- report it. OpenBLAS puts it in "Libs.private", reported only by
-- "pkg-config --libs --static", so we add it to "Libs" as well. OpenBLAS
-- itself uses pthread on every system but Windows.
if use_threads and platform ~= "windows" then
    local libs_line = "Libs: -L${libdir} -l${libprefix}openblas${libsuffix}${libnamesuffix}"
    file_replace("openblas.pc.in", libs_line, libs_line .. " -lpthread")
end

local build_command = {"make"}
util.append_all(build_command, opts)
util.append_all(build_command, targets)
print("Using make command: " .. table.concat(build_command, " "))
run(build_command)

local install_command = {"make"}
util.append_all(install_command, opts)
util.append_all(install_command, {"DESTDIR=" .. destdir, "install"})
print("Using make install command: " .. table.concat(install_command, " "))
run(install_command)

-- make install puts the files in destdir + prefix: move them into the
-- destdir root, as build_and_install does for the other build systems.
local rel = prefix:gsub("^%a:", ""):gsub("^/", ""):gsub("/$", "")
if destdir ~= "" and rel ~= "" then
    local source_dir = destdir .. "/" .. rel
    for _, name in ipairs(util.listdir(source_dir)) do
        os.rename(source_dir .. "/" .. name, destdir .. "/" .. name)
    end
    util.rm_rf(destdir .. "/" .. rel:match("^([^/]*)"))
end
