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
]], spec.cc, spec.cxx, spec.cc, spec.cpu_flags, spec.cxx, spec.cpu_flags,
        spec.cflags or "", spec.cxxflags or "", spec.ldflags or "",
        spec.cpu_type, spec.cpu_target, spec.build_type)
end

local function printf_join(fmt, list)
    local parts = {}
    for _, item in ipairs(list) do
        parts[#parts + 1] = string.format(fmt, item)
    end
    return table.concat(parts, ":")
end

local function activate_script_format(spec, abs_prefix, libdir_array)
    local libdir = libdir_array[1]
    local datadir = abs_prefix .. "/share"
    local pkgconfig_reldir = libdir .. "/pkgconfig"
    local pkgconfig_path = printf_join("$prefix/%s/pkgconfig", libdir_array)
    local ldpath = printf_join("$prefix/%s", libdir_array)
    local ldlibpath_var_name
    if util.platform == "darwin" then
        ldlibpath_var_name = "DYLD_LIBRARY_PATH"
    else
        ldlibpath_var_name = "LD_LIBRARY_PATH"
    end
    local lv = ldlibpath_var_name
    return string.format([[
prefix="%s"
export PATH="$prefix/bin${PATH:+:}$PATH"

export %s="%s${%s:+:}$%s"
if [ -z ${PKG_CONFIG_PATH+x} ]; then
    export PKG_CONFIG_PATH="%s:%s/pkgconfig:%s/pkgconfig"
else
    export PKG_CONFIG_PATH="%s${PKG_CONFIG_PATH:+:}$PKG_CONFIG_PATH"
fi

export CMAKE_PREFIX_PATH="$prefix"
export LHELPER_LIBDIR="%s"
export LHELPER_PKGCONFIG_RPATH="%s"
export LHELPER_ENV_ROOT="%s"
export LHELPER_ENV_PREFIX="$prefix"
export LHELPER_ENV_NAME="%s"
export LHELPER_BUILD_FILENAME="%s"

source "$LHELPER_ENV_PREFIX/bin/lhelper-config"
]], abs_prefix,
        lv, ldpath, lv, lv,
        pkgconfig_path, libdir, datadir,
        pkgconfig_path,
        libdir, pkgconfig_reldir,
        spec.env_root, spec.env_name, spec.build_filename or "")
end

-- Create an environment: directories, lhelper-config and activate script.
-- spec: {env_name=, prefix=, env_source=, build_filename=, cc=, cxx=,
--        cflags=, cxxflags=, ldflags=, cpu_type=, cpu_target=, build_type=}
function env.create_env(spec)
    local cpu_flags = cpu.compiler_flags(spec.cpu_type, spec.cpu_target)
    if not cpu_flags then
        print(string.format("error: Unrecognized CPU type / target combination: %s:%s",
            spec.cpu_type, spec.cpu_target))
        os.exit(1)
    end
    spec.cpu_flags = cpu_flags
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
function env.activate_in_process(prefix, env_root, env_name, build_filename)
    local abs_prefix = util.realpath(prefix)
    local libdir_array = env.default_libdir()
    local function prepend_path(name, value)
        local old = os.getenv(name)
        util.setenv(name, value .. (old and old ~= "" and (":" .. old) or ""))
    end
    prepend_path("PATH", abs_prefix .. "/bin")

    local ldlibpath_var = (util.platform == "darwin") and
        "DYLD_LIBRARY_PATH" or "LD_LIBRARY_PATH"
    local ldpaths = {}
    local pkgconfig_paths = {}
    for _, libdir in ipairs(libdir_array) do
        ldpaths[#ldpaths + 1] = abs_prefix .. "/" .. libdir
        pkgconfig_paths[#pkgconfig_paths + 1] = abs_prefix .. "/" .. libdir .. "/pkgconfig"
    end
    prepend_path(ldlibpath_var, table.concat(ldpaths, ":"))
    if os.getenv("PKG_CONFIG_PATH") == nil then
        util.setenv("PKG_CONFIG_PATH", table.concat(pkgconfig_paths, ":") ..
            ":" .. libdir_array[1] .. "/pkgconfig:" .. abs_prefix .. "/share/pkgconfig")
    else
        prepend_path("PKG_CONFIG_PATH", table.concat(pkgconfig_paths, ":"))
    end

    util.setenv("CMAKE_PREFIX_PATH", abs_prefix)
    util.setenv("LHELPER_LIBDIR", libdir_array[1])
    util.setenv("LHELPER_PKGCONFIG_RPATH", libdir_array[1] .. "/pkgconfig")
    util.setenv("LHELPER_ENV_ROOT", env_root)
    util.setenv("LHELPER_ENV_PREFIX", abs_prefix)
    util.setenv("LHELPER_ENV_NAME", env_name)
    util.setenv("LHELPER_BUILD_FILENAME", build_filename or "")

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
