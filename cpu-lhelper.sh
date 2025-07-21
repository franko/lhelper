
# https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html
# https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html#ARM-Options

# https://en.wikipedia.org/wiki/List_of_Intel_CPU_microarchitectures#x86_microarchitectures
# https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels
# https://en.wikipedia.org/wiki/X86#Chronology

# Clang available march: llc -march=x86-64 -mattr=help
# gcc -march=native -Q --help=target

# We do not cover all the OpenBLAS targets for x86/x86-64
# IMPORTANT: for each "architecture" the first line should be the more basic
#            CPU_TARGET supported. It will be chosen as a default if CPU_TARGET is
#            not given.
# meaning: "architecture", "CPU target's name", ""gcc/clang arch name", "additional flags"
known_cpu_spec=(
    "x86    i586        i586             -m32"
    "x86    i686        i686             -m32"
    "x86    pentium2    pentium2         -m32"
    "x86    pentium3    pentium3         -m32,-mfpmath=sse,-msse"
    "x86    pentium4    pentium4         -m32,-mfpmath=sse,-msse2"
    "x86    prescott    prescott         -m32,-mfpmath=sse,-msse2"
    "x86    nehalem     nehalem          -m32,-mfpmath=sse,-msse2"
    "x86    haswell     haswell          -m32,-mfpmath=sse,-msse2"
    "x86-64 x86-64      x86-64        "
    "x86-64 core2       core2         "
    "x86-64 athlon      athlon        "
    "x86-64 opteron     opteron       "
    "x86-64 barcelona   barcelona     "
    "x86-64 bobcat      btver1        " # Bobcat, 1st gen
    "x86-64 jaguar      btver2        " # Bobcat, 2nd gen
    "x86-64 bulldozer   bdver1        " # Bulldozer, 1st gen
    "x86-64 piledriver  bdver2        "
    "x86-64 steamroller bdver3        "
    "x86-64 excavator   bdver4        "
    "x86-64 zen         znver1        "
    "x86-64 zen2         znver2        "         # Zen 2 (2019)
    "x86-64 zen3         znver3        "         # Zen 3 (2020)
    "x86-64 zen4         znver4        "         # Zen 4 (2022)
    "x86-64 x86-64-v2   x86-64-v2     "
    "x86-64 nehalem     nehalem       "
    "x86-64 westmere    westmere       "
    "x86-64 sandybridge sandybridge   "
    "x86-64 x86-64-v3   x86-64-v3     "
    "x86-64 haswell     haswell       "
    "x86-64 broadwell   broadwell     "
    "x86-64 skylake     skylake       "
    "x86-64 cooperlake  cooperlake    "
    "x86-64 atom        bonnell       "
    "x86-64 x86-64-v4   x86-64-v4     "
    "x86-64 skylakex    skylake-avx512"
    "x86-64 icelake      icelake       "         # Ice Lake (2019)
    "x86-64 tigerlake    tigerlake     "         # Tiger Lake (2020)
    "x86-64 alderlake    alderlake     "         # Alder Lake (2021)
    "x86-64 sapphirerapids sapphirerapids "      # Sapphire Rapids (2023)
    "arm    armv6       armv6         "
    "arm    armv6+fp    armv6+fp      "
    "arm    armv7       armv7         "
    "arm    armv7a      armv7-a       "
    "arm    armv7a+fp   armv7-a+fp    "
    "arm    cortexa15   armv7-a+fp     -mtune=cortex-a15"
    "arm    cortexa9    armv7-a+fp     -mtune=cortex-a9"
    "arm64  armv8       armv8-a       "
    "arm64  cortexa53   armv8-a        -mtune=cortex-a53"
    "arm64  cortexa57   armv8-a        -mtune=cortex-a57"
    "arm64  cortexa72   armv8-a        -mtune=cortex-a72"
    "arm64  cortexa73   armv8-a       "
    "arm64  armv8.2      armv8.2-a     "         # ARMv8.2
    "arm64  armv8.3      armv8.3-a     "         # ARMv8.3
    "arm64  armv8.4      armv8.4-a     "         # ARMv8.4
    "arm64  armv9        armv9-a       "         # ARMv9
    "arm64  cortexa76    armv8.2-a     -mtune=cortex-a76"
    "arm64  cortexa78    armv8.2-a     -mtune=cortex-a78"
    "arm64  cortexX1     armv8.2-a     -mtune=cortex-x1"
    "arm64  neoversen1   armv8.2-a     -mtune=neoverse-n1"
    "arm64  neoversen2   armv8.5-a     -mtune=neoverse-n2"
    "arm64  neoversev1   armv8.4-a     -mtune=neoverse-v1"
)

