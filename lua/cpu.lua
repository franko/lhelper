-- Known CPU architectures and targets, with the corresponding compiler flags.
--
-- https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html
-- https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html#ARM-Options
-- https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels
--
-- Each entry is: architecture, CPU target's name, gcc/clang arch name,
-- additional flags. For each architecture the first line should be the most
-- basic CPU_TARGET supported: it is chosen as a default when CPU_TARGET is
-- not given.

local util = require "util"

local cpu = {}

cpu.known_cpu_spec = {
    {"x86",    "i586",        "i586",           "-m32"},
    {"x86",    "i686",        "i686",           "-m32"},
    {"x86",    "pentium2",    "pentium2",       "-m32"},
    {"x86",    "pentium3",    "pentium3",       "-m32 -mfpmath=sse -msse"},
    {"x86",    "pentium4",    "pentium4",       "-m32 -mfpmath=sse -msse2"},
    {"x86",    "prescott",    "prescott",       "-m32 -mfpmath=sse -msse2"},
    {"x86",    "nehalem",     "nehalem",        "-m32 -mfpmath=sse -msse2"},
    {"x86",    "haswell",     "haswell",        "-m32 -mfpmath=sse -msse2"},
    {"x86-64", "x86-64",      "x86-64",         ""},
    {"x86-64", "core2",       "core2",          ""},
    {"x86-64", "athlon",      "athlon",         ""},
    {"x86-64", "opteron",     "opteron",        ""},
    {"x86-64", "barcelona",   "barcelona",      ""},
    {"x86-64", "bobcat",      "btver1",         ""}, -- Bobcat, 1st gen
    {"x86-64", "jaguar",      "btver2",         ""}, -- Bobcat, 2nd gen
    {"x86-64", "bulldozer",   "bdver1",         ""}, -- Bulldozer, 1st gen
    {"x86-64", "piledriver",  "bdver2",         ""},
    {"x86-64", "steamroller", "bdver3",         ""},
    {"x86-64", "excavator",   "bdver4",         ""},
    {"x86-64", "zen",         "znver1",         ""},
    {"x86-64", "zen2",        "znver2",         ""}, -- Zen 2 (2019)
    {"x86-64", "zen3",        "znver3",         ""}, -- Zen 3 (2020)
    {"x86-64", "zen4",        "znver4",         ""}, -- Zen 4 (2022)
    {"x86-64", "x86-64-v2",   "x86-64-v2",      ""},
    {"x86-64", "nehalem",     "nehalem",        ""},
    {"x86-64", "westmere",    "westmere",       ""},
    {"x86-64", "sandybridge", "sandybridge",    ""},
    {"x86-64", "x86-64-v3",   "x86-64-v3",      ""},
    {"x86-64", "haswell",     "haswell",        ""},
    {"x86-64", "broadwell",   "broadwell",      ""},
    {"x86-64", "skylake",     "skylake",        ""},
    {"x86-64", "cooperlake",  "cooperlake",     ""},
    {"x86-64", "atom",        "bonnell",        ""},
    {"x86-64", "x86-64-v4",   "x86-64-v4",      ""},
    {"x86-64", "skylakex",    "skylake-avx512", ""},
    {"x86-64", "icelake",     "icelake",        ""}, -- Ice Lake (2019)
    {"x86-64", "tigerlake",   "tigerlake",      ""}, -- Tiger Lake (2020)
    {"x86-64", "alderlake",   "alderlake",      ""}, -- Alder Lake (2021)
    {"x86-64", "sapphirerapids", "sapphirerapids", ""}, -- Sapphire Rapids (2023)
    {"arm",    "armv6",       "armv6",          ""},
    {"arm",    "armv6+fp",    "armv6+fp",       ""},
    {"arm",    "armv7",       "armv7",          ""},
    {"arm",    "armv7a",      "armv7-a",        ""},
    {"arm",    "armv7a+fp",   "armv7-a+fp",     ""},
    {"arm",    "cortexa15",   "armv7-a+fp",     "-mtune=cortex-a15"},
    {"arm",    "cortexa9",    "armv7-a+fp",     "-mtune=cortex-a9"},
    {"arm64",  "armv8",       "armv8-a",        ""},
    {"arm64",  "cortexa53",   "armv8-a",        "-mtune=cortex-a53"},
    {"arm64",  "cortexa57",   "armv8-a",        "-mtune=cortex-a57"},
    {"arm64",  "cortexa72",   "armv8-a",        "-mtune=cortex-a72"},
    {"arm64",  "cortexa73",   "armv8-a",        ""},
    {"arm64",  "armv8.2",     "armv8.2-a",      ""},
    {"arm64",  "armv8.3",     "armv8.3-a",      ""},
    {"arm64",  "armv8.4",     "armv8.4-a",      ""},
    {"arm64",  "armv9",       "armv9-a",        ""},
    {"arm64",  "cortexa76",   "armv8.2-a",      "-mtune=cortex-a76"},
    {"arm64",  "cortexa78",   "armv8.2-a",      "-mtune=cortex-a78"},
    {"arm64",  "cortexX1",    "armv8.2-a",      "-mtune=cortex-x1"},
    {"arm64",  "neoversen1",  "armv8.2-a",      "-mtune=neoverse-n1"},
    {"arm64",  "neoversen2",  "armv8.5-a",      "-mtune=neoverse-n2"},
    {"arm64",  "neoversev1",  "armv8.4-a",      "-mtune=neoverse-v1"},
}

-- Compiler flags for a given cpu_type / cpu_target combination or nil.
function cpu.compiler_flags(cpu_type, cpu_target)
    for _, spec in ipairs(cpu.known_cpu_spec) do
        if spec[1] == cpu_type and spec[2] == cpu_target then
            local flags = "-march=" .. spec[3]
            if spec[4] ~= "" then
                flags = flags .. " " .. spec[4]
            end
            return flags
        end
    end
    return nil
end

-- Guess the machine's CPU. Returns cpu_type, cpu_target, help text.
function cpu.guess()
    local machine = util.trim(util.capture({"uname", "-m"}))
    if machine == "x86_64" then
        return "x86-64", "x86-64", [[
# Possible values for CPU_TARGET are:
#
# x86-64 core2 athlon opteron barcelona bobcat jaguar bulldozer piledriver steamroller excavator
# zen x86-64-v2 nehalem westmere sandybridge x86-64-v3 haswell broadwell skylake cooperlake atom
# x86-64-v4 skylakex
#
# You may use a generic CPU architecture for CPU_TARGET like:
#
# x86-64       Support MMX SSE SSE2 FXSR
# x86-64-v2    Support SSE3 SSE4_1 SSE4_2 SSSE3
# x86-64-v3    Support AVX AVX2
# x86-64-v4    Support AVX512
#
# For more informations: https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels]]
    elseif machine == "i586" then
        return "x86", "i586", [[
# For ancient i586 this is the only supported CPU_TARGET.
# It does not support any SIMD extension but has FPU support.
#
# For more information:
#
# https://en.wikipedia.org/wiki/X86#Chronology
# https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html]]
    elseif machine == "i686" then
        return "x86", "i686", [[
# Possible values for CPU_TARGET are:
#
# i686 pentium2 pentium3 pentium4 prescott nehalem haswell
#
# You may use a generic CPU architecture for CPU_TARGET like:
#
# i686         No SIMD extensions
# pentium2     Support MMX FXSR
# pentium3     Support MMX SSE FXSR
# pentium4     Support MMX SSE SSE2 FXSR
#
# For more information:
#
# https://en.wikipedia.org/wiki/X86#Chronology
# https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html]]
    elseif machine:match("^arm64") or machine == "aarch64" then
        return "arm64", "armv8", [[
# Possible values for CPU_TARGET are:
#
# armv8 cortexa53 cortexa57 cortexa72 cortexa73
#
# You may use a generic CPU architecture for CPU_TARGET like armv8.
#
# For more information:
#
# https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html#ARM-Options]]
    elseif machine:match("^arm") then
        return "arm", "armv6", [[
# Possible values for CPU_TARGET are:
#
# armv6 armv6+fp armv7 armv7a armv7a+fp cortexa9 cortexa15
#
# You may use a generic CPU architecture for CPU_TARGET like:
#
# armv6        No FPU support
# armv6+fp     Include VFPv2 support
# armv7        No FPU support
# armv7a       No FPU support
# armv7a+fp    Include VFPv3 support
#
# For more information:
#
# https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html#ARM-Options]]
    end
    return "unknown", "unknown",
        "# The CPU type is unknown. You may contact the lhelper developers."
end

-- Fill in cpu_type and/or cpu_target when one of them is missing, following
-- the same logic of the original bash implementation.
-- Returns cpu_type, cpu_target or nil, error message.
function cpu.resolve(cpu_type, cpu_target, type_guess, target_guess)
    if not cpu_type and not cpu_target then
        print(string.format("Using CPU_TYPE=%s and CPU_TARGET=%s", type_guess, target_guess))
        return type_guess, target_guess
    end
    if not cpu_type then
        -- CPU_TARGET given but not CPU_TYPE: find the types providing this target
        local types = {}
        for _, spec in ipairs(cpu.known_cpu_spec) do
            if spec[2] == cpu_target and not util.contains(types, spec[1]) then
                types[#types + 1] = spec[1]
            end
        end
        if util.contains(types, type_guess) then
            cpu_type = type_guess
        else
            cpu_type = types[1]
        end
        if not cpu_type then
            return nil, "cannot find CPU_TYPE for " .. cpu_target
        end
        print("Using CPU_TYPE=" .. cpu_type)
        return cpu_type, cpu_target
    end
    if not cpu_target then
        -- CPU_TYPE given but not CPU_TARGET: take the first matching entry
        for _, spec in ipairs(cpu.known_cpu_spec) do
            if spec[1] == cpu_type then
                print("Using CPU_TARGET=" .. spec[2])
                return cpu_type, spec[2]
            end
        end
        return nil, "cannot find CPU_TARGET for " .. cpu_type
    end
    return cpu_type, cpu_target
end

return cpu
