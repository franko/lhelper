-- Environment creation and activation.
--
-- An environment is a directory containing bin/, include/, lib dirs, the
-- "lhelper-config" file with the compiler variables and the "activate"
-- script sourced by bash. The activate script is kept as a bash script by
-- design: its purpose is to export variables in the user's shell.

local util = require "util"
local cpu = require "cpu"

local env = {}

-- Figure out the default library directories.
-- Adapted from mesonbuild/mesonlib.py. Returns one or more directories:
-- on debian with multiarch there is the lib directory and its multiarch
-- subdirectory. The first directory will be used by lhelper to install new
-- pkg-config files if the build system doesn't do it natively.
function env.default_libdir()
    if util.is_file("/etc/debian_version") then
        local archpath, code = util.capture({"dpkg-architecture", "-qDEB_HOST_MULTIARCH"})
        archpath = util.trim(archpath)
        if code == 0 and archpath ~= "" then
            return { "lib/" .. archpath, "lib" }
        end
    end
    local st = require("lhsys").stat("/usr/lib64", "l")
    if st and st.type == "dir" then
        return { "lib64" }
    end
    return { "lib" }
end

-- Parse a lhelper-config file (bash "export NAME=..." lines) into a table.
function env.parse_config(filename)
    local config = {}
    for _, line in ipairs(util.read_lines(filename)) do
        local name, value = line:match('^export%s+([%w_]+)="(.-)"%s*$')
        if not name then
            name, value = line:match('^export%s+([%w_]+)=(%S*)%s*$')
        end
        if name then config[name] = value end
    end
    return config
end

-- The lhelper-config block declaring the packages taken from the system
-- libraries instead of the lhelper recipes. Written only when the spec asks
-- for it, so that the environments created without the option keep matching
-- their configuration file.
local function prefer_system_format(spec)
    if not spec.prefer_system_libraries then return "" end
    return string.format([[

# Packages taken from the system libraries instead of being built from a
# lhelper recipe: "*" for every package or the package names separated by
# spaces.
export LHELPER_PREFER_SYSTEM_LIBRARIES="%s"
]], spec.prefer_system_libraries)
end

local function config_format(spec)
    return string.format([[
# Edit here the compiler variables and flags for this
# specific environment.

# Avoid using generic debug or optimization flags as they
# are automatically added by cmake or meson depending on
# the BUILD_TYPE variable.

export CC_BARE="%s"
export CXX_BARE="%s"
export CC="%s %s"
export CXX="%s %s"
export CFLAGS="%s"
export CXXFLAGS="%s"
export LDFLAGS="%s"
export CPU_TYPE="%s"
export CPU_TARGET="%s"

# Can be Release or Debug
export BUILD_TYPE="%s"
%s]], spec.cc, spec.cxx, spec.cc, spec.cpu_flags, spec.cxx, spec.cpu_flags,
        spec.cflags or "", spec.cxxflags or "", spec.ldflags or "",
        spec.cpu_type, spec.cpu_target, spec.build_type,
        prefer_system_format(spec))
end

-- The environment variables that define an activated environment, as an
-- ordered list of operations. This is the single source of truth used both
-- to generate the bash "activate" script (serialize_activation, sourced by
-- the user's subshell) and to set the same variables in lhelper's own
-- process (apply_activation, so package builds run inside the environment).
-- Each entry is { name=, value=, prepend=, default= }:
--   prepend   the value is prepended to the variable's current content;
--   default   when the variable is unset this value is used instead of
--             prepending (only PKG_CONFIG_PATH needs it).
-- The paths are absolute (abs_prefix inlined) rather than expressed through
-- a bash "prefix" variable, so the very same entries can be applied
-- in-process, where no shell expansion happens.
local function activation_entries(env_root, env_name, abs_prefix, libdir_array)
    local ldlibpath_var = (util.platform == "darwin") and
        "DYLD_LIBRARY_PATH" or "LD_LIBRARY_PATH"
    local ldpaths, pkgconfig_paths = {}, {}
    for _, libdir in ipairs(libdir_array) do
        ldpaths[#ldpaths + 1] = abs_prefix .. "/" .. libdir
        pkgconfig_paths[#pkgconfig_paths + 1] = abs_prefix .. "/" .. libdir .. "/pkgconfig"
    end
    local pkgconfig_value = table.concat(pkgconfig_paths, ":")
    return {
        { name = "PATH", value = abs_prefix .. "/bin", prepend = true },
        { name = ldlibpath_var, value = table.concat(ldpaths, ":"), prepend = true },
        -- NOTE: the unset ("default") case keeps a bare relative
        -- "lib/pkgconfig" entry, carried over verbatim from the original
        -- implementation.
        { name = "PKG_CONFIG_PATH", value = pkgconfig_value, prepend = true,
          default = pkgconfig_value .. ":" .. libdir_array[1] .. "/pkgconfig:" ..
              abs_prefix .. "/share/pkgconfig" },
        { name = "CMAKE_PREFIX_PATH", value = abs_prefix },
        { name = "LHELPER_LIBDIR", value = libdir_array[1] },
        { name = "LHELPER_PKGCONFIG_RPATH", value = libdir_array[1] .. "/pkgconfig" },
        { name = "LHELPER_ENV_ROOT", value = env_root },
        { name = "LHELPER_ENV_PREFIX", value = abs_prefix },
        { name = "LHELPER_ENV_NAME", value = env_name },
    }
end

-- Serialize the activation entries as bash "export" lines.
local function serialize_activation(entries)
    local lines = {}
    for _, e in ipairs(entries) do
        if e.default then
            lines[#lines + 1] = string.format(
                'if [ -z ${%s+x} ]; then\n    export %s="%s"\nelse\n' ..
                '    export %s="%s${%s:+:}$%s"\nfi',
                e.name, e.name, e.default, e.name, e.value, e.name, e.name)
        elseif e.prepend then
            lines[#lines + 1] = string.format('export %s="%s${%s:+:}$%s"',
                e.name, e.value, e.name, e.name)
        else
            lines[#lines + 1] = string.format('export %s="%s"', e.name, e.value)
        end
    end
    return table.concat(lines, "\n")
end

-- Apply the activation entries to lhelper's own process environment.
local function apply_activation(entries)
    for _, e in ipairs(entries) do
        if e.default and os.getenv(e.name) == nil then
            util.setenv(e.name, e.default)
        elseif e.prepend then
            local old = os.getenv(e.name)
            util.setenv(e.name, e.value ..
                (old and old ~= "" and (":" .. old) or ""))
        else
            util.setenv(e.name, e.value)
        end
    end
end

local function activate_script_format(spec, abs_prefix, libdir_array)
    local entries = activation_entries(spec.env_root, spec.env_name,
        abs_prefix, libdir_array)
    return serialize_activation(entries) ..
        '\n\nsource "$LHELPER_ENV_PREFIX/bin/lhelper-config"\n'
end

-- Compute (and store into spec.cpu_flags) the compiler flags for the
-- spec's CPU type and target.
function env.compute_cpu_flags(spec)
    if spec.cpu_flags then return true end
    local cpu_flags = cpu.compiler_flags(spec.cpu_type, spec.cpu_target)
    if not cpu_flags then
        return nil, string.format("Unrecognized CPU type / target combination: %s:%s",
            spec.cpu_type, spec.cpu_target)
    end
    spec.cpu_flags = cpu_flags
    return true
end

-- The content of the environment's lhelper-config file for a build spec.
function env.config_content(spec)
    return config_format(spec)
end

-- The configuration values of a build spec, as the table that
-- parse_config would return for the corresponding lhelper-config file.
function env.spec_config(spec)
    return {
        CC_BARE = spec.cc,
        CXX_BARE = spec.cxx,
        CC = spec.cc .. " " .. spec.cpu_flags,
        CXX = spec.cxx .. " " .. spec.cpu_flags,
        CFLAGS = spec.cflags or "",
        CXXFLAGS = spec.cxxflags or "",
        LDFLAGS = spec.ldflags or "",
        CPU_TYPE = spec.cpu_type,
        CPU_TARGET = spec.cpu_target,
        BUILD_TYPE = spec.build_type,
        LHELPER_PREFER_SYSTEM_LIBRARIES = spec.prefer_system_libraries,
    }
end

-- Create an environment: directories, lhelper-config and activate script.
-- spec: {env_name=, prefix=, env_source=, cc=, cxx=,
--        cflags=, cxxflags=, ldflags=, cpu_type=, cpu_target=, build_type=,
--        prefer_system_libraries=}
function env.create_env(spec)
    local ok, err = env.compute_cpu_flags(spec)
    if not ok then
        print("error: " .. err)
        os.exit(1)
    end
    spec.env_root = require("lhsys").getcwd()

    local prefix = spec.prefix
    local libdir_array = env.default_libdir()
    for _, libdir in ipairs(libdir_array) do
        util.mkdir_p(prefix .. "/" .. libdir .. "/pkgconfig")
    end
    util.mkdir_p(prefix .. "/include")
    util.mkdir_p(prefix .. "/bin")
    util.mkdir_p(prefix .. "/packages/" .. os.getenv("LHELPER_PACKAGE_VERSION"))
    util.mkdir_p(prefix .. "/logs")

    if not util.is_file(prefix .. "/bin/lhelper-packages") then
        util.write_file(prefix .. "/bin/lhelper-packages", "")
    end
    -- To avoid deleting the directories when removing packages
    util.write_file(prefix .. "/logs/.keep", "")
    util.write_file(prefix .. "/packages/" ..
        os.getenv("LHELPER_PACKAGE_VERSION") .. "/.keep", "")

    util.write_file(prefix .. "/bin/lhelper-config", config_format(spec))
    local abs_prefix = util.realpath(prefix)
    util.write_file(spec.env_source,
        activate_script_format(spec, abs_prefix, libdir_array))
end

-- Set in the current process the same variables the activate script would
-- set in a shell, so that the packages installs run within the environment.
function env.activate_in_process(prefix, env_root, env_name)
    local abs_prefix = util.realpath(prefix)
    local libdir_array = env.default_libdir()
    apply_activation(activation_entries(env_root, env_name, abs_prefix, libdir_array))

    -- source lhelper-config
    local config = env.parse_config(abs_prefix .. "/bin/lhelper-config")
    for name, value in pairs(config) do
        util.setenv(name, value)
    end
end

-------------------------------------------------------------------------------
-- OS identification (used for the build environment digest)

function env.find_os_release()
    local uname_out = util.trim(util.capture({"uname", "-s"}))
    if uname_out:match("^Linux") then
        if util.is_file("/etc/os-release") then
            local id, version_id
            for _, line in ipairs(util.read_lines("/etc/os-release")) do
                local name, value = line:match('^([%w_]+)="?([^"]*)"?%s*$')
                if name == "ID" then id = value end
                if name == "VERSION_ID" then version_id = value end
            end
            return (id or "linux") .. "-" .. (version_id or "unknown")
        elseif util.is_file("/etc/redhat-release") then
            local rh_line = util.read_file("/etc/redhat-release") or ""
            local release = rh_line:match("Red Hat .* release (%S+)")
            return "rhel-" .. (release or "unknown")
        elseif util.which("lsb_release") then
            local dist = util.trim(util.capture({"lsb_release", "-i"})):match("\t(.*)$")
            local release = util.trim(util.capture({"lsb_release", "-r"})):match("\t(.*)$")
            if dist and release then
                return dist .. "-" .. release
            end
        end
        return "linux-unknown"
    end
    -- On MSYS2 the output is like MINGW32_NT-10.0-17763
    local short = uname_out:match("^([^%-]+%-[^%-]+)")
    return short or uname_out
end

function env.get_compiler_version(cc)
    local argv = util.split(cc)
    argv[#argv + 1] = "--version"
    local output = util.capture(argv)
    local first_line = output:match("^[^\n]*") or ""
    local gcc_name, gcc_ver = first_line:match("^gcc.*%((.*)%)%s+(%d+)%.%d+")
    if gcc_name then
        return string.format("gcc (%s) %s", gcc_name, gcc_ver)
    end
    local gxx_name, gxx_ver = first_line:match("^g%+%+.*%((.*)%)%s+(%d+)%.%d+")
    if gxx_name then
        return string.format("g++ (%s) %s", gxx_name, gxx_ver)
    end
    local clang_ver = first_line:match("clang%s+version%s+(%d+)%.%d+")
    if clang_ver then
        return "clang " .. clang_ver
    end
    return first_line
end

return env
