-- lhelper main program.

local util = require "util"
local lhsys = require "lhsys"
local cpu = require "cpu"
local env = require "env"
local pkg = require "pkg"
local installer = require "install"

local command_name = util.basename(arg[0] or "lhelper")

if #arg < 1 then
    print(string.format("Usage: %s <command> [<other options>]", command_name))
    os.exit(1)
end

-------------------------------------------------------------------------------
-- initialization

-- lhelper directories: the lua modules are in <LHELPER_DIR>/lua so the
-- parent directory of the modules is used. This works both for an installed
-- lhelper (<prefix>/share/lhelper/lua) and when running from the source
-- tree with the LHELPER_LUA_DIR variable set.
local lhelper_dir = util.dirname(LHELPER_LUA_DIR)
local lhelper_prefix
do
    local bin_dir = util.dirname(LHELPER_EXE_PATH)
    lhelper_prefix = bin_dir:gsub("/bin$", "")
end
if os.getenv("LHELPER_LUA_DIR") then
    -- running from the source tree: use a local var directory
    lhelper_prefix = lhelper_dir
end

local lhelper_tmpdir
if util.is_windows then
    lhelper_tmpdir = "C:/Windows/Temp"
else
    lhelper_tmpdir = os.getenv("TMPDIR") or "/tmp"
    lhelper_tmpdir = lhelper_tmpdir:gsub("/$", "")
end

util.setenv("LHELPER_SYSTEM_PREFIX", "/usr")
util.setenv("LHELPER_PACKAGE_VERSION", os.getenv("LHELPER_PACKAGE_VERSION") or "2")
util.setenv("LHELPER_WORKING_DIR", lhelper_prefix .. "/var/lhelper")
util.setenv("LHELPER_DIR", lhelper_dir)
util.setenv("LHELPER_TMPDIR", lhelper_tmpdir)

local working_dir = os.getenv("LHELPER_WORKING_DIR")

-- config files and directory used by lhelper
local home_dir = os.getenv("HOME") or ""
local config_dir = home_dir .. "/.config/lhelper"
local config_filename = config_dir .. "/config"

-- The LH_SSH_KEY_PATH variable defines if we have a ssh key or not. If set
-- it is the full path of the ssh private key filename.
util.setenv("LH_SSH_KEY_PATH", nil)
util.setenv("LH_SSH_KEY_PORT", nil)
if util.is_file(config_filename) then
    for _, line in ipairs(util.read_lines(config_filename)) do
        local name, value = line:match('^export%s+([%w_]+)="?([^"]*)"?%s*$')
        if name then util.setenv(name, value) end
    end
end

for _, dir in ipairs({ working_dir .. "/packages/" .. os.getenv("LHELPER_PACKAGE_VERSION"),
    working_dir .. "/archives", working_dir .. "/digests" }) do
    if not util.is_dir(dir) then
        local ok = util.mkdir_p(dir)
        if not ok then
            io.stderr:write("error: cannot create directory " .. dir .. "\n")
            os.exit(1)
        end
    end
end

-- On MSYS unix-like absolute paths like /home/user are fed to the native
-- applications transformed into the real windows path like
-- C:/msys64/home/user. The LH_MSYSROOT variable lets lhelper recognize the
-- msys root windows path, C:/msys64/, and treat it as if it were "/".
if util.which("cygpath") then
    util.setenv("LH_MSYSROOT", util.trim(util.capture({"cygpath", "-m", "/"})))
end

if not util.is_dir(lhelper_dir) then
    print(string.format("error: directory \"%s\" not found.", lhelper_dir))
    print("Lhelper may be not properly installed.")
end

-------------------------------------------------------------------------------
-- helpers

local function check_env_active_or_exit()
    if not os.getenv("LHELPER_ENV_NAME") then
        print("No environment activated")
        print("To list the packages an environment should be activated")
        os.exit(1)
    end
end

local function find_editor()
    local editor = os.getenv("EDITOR")
    if editor then return editor end
    io.stderr:write("Information: the EDITOR variable is not set: choosing a terminal editor\n")
    io.stderr:write("from those available.\n")
    io.stderr:write("You may configure the EDITOR variable to define your editor.\n")
    -- List the most commonly used editors from the easiest to use to the
    -- most specific one. vim near the end is wanted because people not
    -- familiar with vim can get easily stuck.
    for _, editor_name in ipairs({"nano", "micro", "emacs", "vim", "nvim"}) do
        if util.which(editor_name) then
            return editor_name
        end
    end
    return nil
end

local function run_editor(filename)
    local editor = find_editor()
    if not editor then
        print("error: no editor found")
        os.exit(1)
    end
    util.spawn({editor, filename})
end

local function print_installed_packages()
    local packages_file = os.getenv("LHELPER_ENV_PREFIX") .. "/bin/lhelper-packages"
    local lines = util.read_lines(packages_file)
    if #lines > 0 then
        print("Installed packages")
        print("")
        for _, line in ipairs(lines) do
            local line_p, digest = line:match("^(.*) (%S+)$")
            if line_p then
                local pprov, pimpl = line_p:match("^(.-) : (.*)$")
                if pprov then
                    print(string.format("* %s [provided by %s (%s)]",
                        pprov, pimpl, digest:sub(1, 8)))
                else
                    print(string.format("* %s (%s)", line_p, digest:sub(1, 8)))
                end
            end
        end
        print("")
    else
        print("No package installed.")
    end
end

-- Start the environment subshell.
local function start_subshell()
    print_installed_packages()
    print("Starting a new shell with the new environment")
    util.spawn({"bash", "--init-file", lhelper_dir .. "/lhelper-bash-init"})
end

-------------------------------------------------------------------------------
-- build spec (.lhelper) file handling

-- Load a .lhelper build spec file. The file is a simple Lua script setting
-- the variables: cc, cxx, cflags, cxxflags, ldflags, cpu_type, cpu_target,
-- build_type and the list "packages".
local function load_build_spec(build_filename)
    local content, err = util.read_file(build_filename)
    if not content then
        print("error: cannot read the file " .. build_filename)
        os.exit(1)
    end
    local spec_env = { getenv = os.getenv, os = os, string = string }
    local chunk, load_err = load(content, "@" .. build_filename, "t", spec_env)
    if not chunk then
        print("error loading " .. build_filename .. ": " .. load_err)
        os.exit(1)
    end
    local ok, run_err = pcall(chunk)
    if not ok then
        print("error in " .. build_filename .. ": " .. tostring(run_err))
        os.exit(1)
    end
    local spec = {
        cc = spec_env.cc or "gcc",
        cxx = spec_env.cxx or "g++",
        cflags = spec_env.cflags or "",
        cxxflags = spec_env.cxxflags or "",
        ldflags = spec_env.ldflags or "",
        cpu_type = spec_env.cpu_type,
        cpu_target = spec_env.cpu_target,
        build_type = spec_env.build_type or "Release",
        packages = spec_env.packages or {},
    }
    if spec.build_type ~= "Release" and spec.build_type ~= "Debug" then
        print("Build type should be either Release or Debug, abort.")
        os.exit(1)
    end
    return spec
end

local function spec_template(cpu_type_guess, cpu_target_guess, cpu_help, ini_packages)
    local flags_lines = {}
    for _, entry in ipairs({{"cflags", "CFLAGS"}, {"cxxflags", "CXXFLAGS"},
        {"ldflags", "LDFLAGS"}}) do
        local value = os.getenv(entry[2])
        if value then
            flags_lines[#flags_lines + 1] = string.format('%s = "%s"', entry[1], value)
        else
            flags_lines[#flags_lines + 1] = string.format('-- %s = ""', entry[1])
        end
    end
    local packages_lines = {}
    for _, name in ipairs(ini_packages) do
        packages_lines[#packages_lines + 1] = string.format('    "%s",', name)
    end
    return string.format([[
-- This is a Lua script read by lhelper to configure the build toolchain
-- for the environment.

-- Set the variables cc and cxx to the C and C++ compilers to use.
-- They may contain options by separating them with spaces.
cc = getenv("CC") or "gcc"
cxx = getenv("CXX") or "g++"

-- Optional C/C++ and linker flags. Do not include optimization or debug
-- flags, they are automatically added based on the variables build_type,
-- cpu_type and cpu_target.
%s

-- CPU architecture type and specific CPU to target.
%s
--
-- If cpu_type and cpu_target are not given they will be chosen based on the
-- system currently used. You may set some specific value below to force a
-- build for a specific architecture.
--
-- cpu_type = "%s"
-- cpu_target = "%s"

-- Can be "Release" or "Debug". Debug builds the libraries including debug
-- information. If omitted it will default to a release build.
build_type = getenv("BUILD_TYPE") or "Release"

-- List of the libraries to be installed. Each entry is a string with the
-- library name possibly followed by its options separated by spaces.
-- For example:
-- packages = { "freetype2", "sdl2 -opengl" }
packages = {
%s
}
]], table.concat(flags_lines, "\n"),
        cpu_help:gsub("CPU_TARGET", "cpu_target"):gsub("^#", "--"):gsub("\n#", "\n--"),
        cpu_type_guess, cpu_target_guess,
        table.concat(packages_lines, "\n"))
end

-------------------------------------------------------------------------------
-- create / activate command

local function activate_command(args)
    local command = args[1]
    if #args < 2 then
        print(string.format("Usage: %s activate [options] <spec-filename>", command_name))
        os.exit(1)
    end
    installer.lib_install_mode = "verbose"
    local edit_file = false
    local build_filename
    local ini_packages = {}
    local i = 2
    while i <= #args do
        local a = args[i]
        if a == "-e" or a == "--edit" then
            edit_file = true
        elseif a == "--show-dependencies" then
            installer.show_dependencies = true
        elseif a == "--packages" then
            for k = i + 1, #args do
                ini_packages[#ini_packages + 1] = args[k]
            end
            break
        elseif util.starts_with(a, "-") then
            print("error: unknown option " .. a)
            os.exit(1)
        else
            if build_filename then
                print("error: multiple package names")
                os.exit(1)
            end
            build_filename = a
        end
        i = i + 1
    end

    if not util.is_file(build_filename) and
        not util.ends_with(build_filename, ".lhelper") then
        build_filename = build_filename .. ".lhelper"
    end
    local build_basename = util.basename(build_filename)

    local cpu_type_guess, cpu_target_guess, cpu_help = cpu.guess()

    if (edit_file or command == "create") and not util.is_file(build_filename) then
        util.write_file(build_filename, spec_template(cpu_type_guess,
            cpu_target_guess, cpu_help, ini_packages))
    end
    if edit_file then
        run_editor(build_filename)
    end
    if command == "activate" and not util.is_file(build_filename) then
        print(string.format("error: the file %s does not exist or is not a file",
            build_filename))
        os.exit(1)
    end

    local build_realpath = util.realpath(build_filename)
    local env_workdir = util.dirname(build_realpath) .. "/.lhelper"
    if not util.is_dir(env_workdir) then
        if not util.mkdir_p(env_workdir) then
            print("error: cannot create local environment directory: " .. env_workdir)
            os.exit(1)
        end
    end

    local env_test_name = build_basename:gsub("%.lhelper$", "")

    local build_spec = load_build_spec(build_filename)
    local cpu_type, cpu_target, cpu_err = cpu.resolve(build_spec.cpu_type,
        build_spec.cpu_target, cpu_type_guess, cpu_target_guess)
    if not cpu_type then
        print("error: " .. cpu_err)
        os.exit(1)
    end
    build_spec.cpu_type, build_spec.cpu_target = cpu_type, cpu_target

    local env_loaded, install_plans = installer.load_matching_env(
        env_test_name, env_workdir, build_spec)
    if not env_loaded then
        -- Create a new environment.
        local env_prefix = env_workdir .. "/" .. env_test_name
        util.rm_rf(env_prefix)
        local env_spec = {
            env_name = env_test_name,
            prefix = env_prefix,
            env_source = env_prefix .. "/bin/activate",
            cc = build_spec.cc, cxx = build_spec.cxx,
            cflags = build_spec.cflags, cxxflags = build_spec.cxxflags,
            ldflags = build_spec.ldflags,
            cpu_type = build_spec.cpu_type, cpu_target = build_spec.cpu_target,
            build_type = build_spec.build_type,
        }
        env.create_env(env_spec)
        -- install the packages, with the environment activated
        env.activate_in_process(env_prefix, lhsys.getcwd(), env_test_name)
        installer.update_installed_packages(install_plans)
    end

    if command == "activate" then
        start_subshell()
    end
end

-------------------------------------------------------------------------------
-- other commands

local function install_command(args)
    if #args < 2 then
        print(string.format("Usage: %s install <library-name> [version]", command_name))
        os.exit(1)
    end
    check_env_active_or_exit()
    installer.lib_install_mode = "verbose"
    local flags = {}
    local i = 2
    while i <= #args and (args[i] == "--local" or args[i] == "--rebuild") do
        if args[i] == "--local" then flags.local_recipe = true end
        if args[i] == "--rebuild" then flags.rebuild = true end
        i = i + 1
    end
    local install_args = { table.unpack(args, i) }
    installer.library_check_and_install(flags, install_args)
end

local function env_source_command(args)
    if #args ~= 2 then
        print(string.format("Usage: %s env-source <spec-filename>", command_name))
        os.exit(1)
    end
    local env_name = args[2]:gsub("%.lhelper$", "")
    local env_root = os.getenv("LHELPER_ENV_ROOT")
    local env_dir = (env_root and (env_root .. "/") or "") .. ".lhelper"
    if util.is_file(env_name .. ".lhelper") and
        util.is_dir(env_dir .. "/" .. env_name .. "/bin") then
        print(env_dir .. "/" .. env_name .. "/bin/activate")
    else
        print("error: invalid environment name: " .. args[2])
        print("The spec file \"" .. env_name .. ".lhelper\" does not exit or the environment")
        print("is not yet created. You may need to run the \"create\" command.")
        os.exit(1)
    end
end

local function update_command(args)
    if args[2] == "recipes" then
        local recipes_dir = installer.recipes_dir()
        print("Updating recipes")
        local branch_name = util.trim(util.capture({"git", "rev-parse",
            "--abbrev-ref", "HEAD"}, { cwd = recipes_dir }))
        util.spawn({"git", "fetch", "origin", branch_name}, { cwd = recipes_dir })
        util.spawn({"git", "checkout", "-q", "-f", branch_name}, { cwd = recipes_dir })
        util.spawn({"git", "reset", "--hard", "origin/" .. branch_name},
            { cwd = recipes_dir })
    else
        print(string.format("Usage: %s update recipes", command_name))
        os.exit(1)
    end
end

local function register_command(args)
    if args[2] == "key" and args[3] and args[4] then
        if not util.is_file(args[3]) then
            print("The specified SSH key " .. args[3] .. " does not exist.")
            os.exit(1)
        end
        util.mkdir_p(config_dir)
        if os.getenv("LH_SSH_KEY_PATH") then
            print("Warning: the new SSH key will replace the previous one: " ..
                os.getenv("LH_SSH_KEY_PATH"))
        end
        util.write_file(config_filename, string.format(
            'export LH_SSH_KEY_PATH="%s"\nexport LH_SSH_KEY_PORT=%s\n',
            args[3], args[4]))
        util.setenv("LH_SSH_KEY_PATH", args[3])
        util.setenv("LH_SSH_KEY_PORT", args[4])
        print("SSH key registered successfully.")
    else
        print(string.format(
            "Usage: %s register key <ssh-key-filename> <port-number>", command_name))
        os.exit(1)
    end
end

local function list_command(args)
    if args[2] == "recipes" then
        for _, name in ipairs(util.listdir(installer.recipes_dir())) do
            if name ~= "index" then
                print((name:gsub("%.lua$", "")))
            end
        end
    elseif args[2] == "packages" then
        check_env_active_or_exit()
        print_installed_packages()
    elseif args[2] == "files" and args[3] then
        check_env_active_or_exit()
        local list_filename = pkg.package_list_filename(
            os.getenv("LHELPER_ENV_PREFIX"), args[3])
        io.write(util.read_file(list_filename) or "")
    else
        print(string.format(
            "Usage: %s list (files|packages|recipes) [package]", command_name))
        os.exit(1)
    end
end

-------------------------------------------------------------------------------
-- required commands check

-- The compiler gcc or clang is checked when installing lhelper.
-- tar, gzip, git and curl are essential to fetch and pack or unpack source
-- code and compiled packages. make is checked here as well because it is a
-- very standard command required to compile many projects. Other commands
-- possibly needed (cmake, meson, ninja, ...) are verified by each recipe.
local required_commands = {"tar", "gzip", "git", "curl", "pkg-config", "make"}
if util.is_file("/etc/debian_version") then
    required_commands[#required_commands + 1] = "dpkg-architecture"
end
for _, command in ipairs(required_commands) do
    if not util.which(command) then
        io.stderr:write(string.format(
            "error: command \"%s\" is required but it's not available\n", command))
        print("Make sure the commands: " ..
            table.concat(required_commands, " ") .. " are all available.")
        os.exit(1)
    end
end

-------------------------------------------------------------------------------
-- command dispatch

local commands = {}

commands["install"] = install_command
commands["create"] = activate_command
commands["activate"] = activate_command
commands["env-source"] = env_source_command
commands["update"] = update_command
commands["register"] = register_command
commands["list"] = list_command

commands["cleanup"] = function()
    local env_root = os.getenv("LHELPER_ENV_ROOT")
    local clean_env_dir = (env_root and (env_root .. "/") or "") .. ".lhelper"
    if util.is_dir(clean_env_dir) then
        print("Cleaning up the environments stored in \"" .. clean_env_dir .. "\"")
        for _, name in ipairs(util.listdir(clean_env_dir)) do
            util.rm_rf(clean_env_dir .. "/" .. name)
        end
    end
end

commands["remove"] = function(args)
    if #args < 2 then
        print(string.format("Usage: %s remove <library-name>", command_name))
        os.exit(1)
    end
    check_env_active_or_exit()
    installer.library_remove(args[2])
end

commands["dir"] = function()
    check_env_active_or_exit()
    print(os.getenv("LHELPER_ENV_PREFIX"))
end

local command_fn = commands[arg[1]]
if not command_fn then
    print("error: unknown command " .. arg[1])
    os.exit(1)
end

local ok, err = pcall(command_fn, arg)
if not ok then
    if type(err) == "table" and err.msg then
        io.stderr:write(err.msg .. "\n")
    else
        io.stderr:write("lhelper: " .. tostring(err) .. "\n")
    end
    os.exit(1)
end
