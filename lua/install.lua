-- Package install orchestration: run recipes, package the build results,
-- install them into an environment and keep the environment's package list
-- up to date.
--
-- The information flow is kept in memory: the recipes' "dependencies"
-- phase returns the declared dependencies and provided virtual packages as
-- Lua values and the desired state of an environment is computed from the
-- build spec without touching the disk. The only files used are the
-- persistent ones: the lhelper-packages registry, the per-package .list
-- files, the archives/packages caches and the build logs.

local util = require "util"
local lhsys = require "lhsys"
local pkg = require "pkg"
local env = require "env"
local recipe = require "recipe"
local md5 = require "md5"
local pathreplace = require "pathreplace"

local installer = {}

-- install message mode: "verbose" or "quiet"
installer.lib_install_mode = "verbose"
installer.show_dependencies = false

local function msg(...)
    if installer.lib_install_mode == "verbose" then
        print(...)
    end
end

local function getenv(name)
    return os.getenv(name) or ""
end

local function package_dir()
    return getenv("LHELPER_WORKING_DIR") .. "/packages/" .. getenv("LHELPER_PACKAGE_VERSION")
end

-------------------------------------------------------------------------------
-- recipes lookup

function installer.recipes_dir()
    return getenv("LHELPER_DIR") .. "/recipes"
end

function installer.latest_package_version(package)
    local index_filename = installer.recipes_dir() .. "/index"
    for _, line in ipairs(util.read_lines(index_filename)) do
        local name, version = line:match("^(%S+)%s+(%S+)")
        if name == package then return version end
    end
    return nil
end

-- Find the recipe file for a package and version in a directory. Matches
-- "<package>_<version>.lua" or "<package>_<version>+<n>.lua"; the latest
-- one wins. Returns the file name without directory.
function installer.find_recipe_filename(recipe_dir, package, version)
    local recipe_filename
    local exact = package .. "_" .. version .. ".lua"
    local plus_prefix = package .. "_" .. version .. "+"
    for _, name in ipairs(util.listdir(recipe_dir)) do
        if name == exact or
            (util.starts_with(name, plus_prefix) and util.ends_with(name, ".lua")) then
            recipe_filename = name
        end
    end
    return recipe_filename
end

-------------------------------------------------------------------------------
-- remote packages repository

local LHELPER_DOMAIN = "lhelper.cc"
local LHELPER_WWW_DOMAIN = "https://www.lhelper.cc"

local function urlencode(s)
    return (s:gsub("[^%w.~_%-]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function check_remote_package(package_version, package_name)
    local url = string.format("%s/packages/%s/%s", LHELPER_WWW_DOMAIN,
        package_version, package_name)
    return util.run_ok({"curl", "--output",
        util.is_windows and "NUL" or "/dev/null",
        "--silent", "--head", "--fail", url})
end

local function download_package(package_version, package_name, destdir)
    local url = string.format("%s/packages/%s/%s", LHELPER_WWW_DOMAIN,
        package_version, urlencode(package_name))
    local output_file = string.format("%s/%s/%s", destdir, package_version, package_name)
    local null = util.is_windows and "NUL" or "/dev/null"
    return util.run_ok({"curl", "-L", url, "-o", output_file},
        { stdout = null, stderr = null })
end

local function upload_package(package_version, package_filename)
    local package_name = util.basename(package_filename)
    local package_url = package_version .. "/" .. urlencode(package_name)
    -- Check if the file already exists on the server
    local response = util.trim(util.capture({"curl", "-s", "-o",
        util.is_windows and "NUL" or "/dev/null", "-w", "%{http_code}",
        LHELPER_WWW_DOMAIN .. "/packages/" .. package_url}))
    if response ~= "200" then
        local dest = string.format("lhelper@%s:/lhelper/files/%s/%s",
            LHELPER_DOMAIN, package_version, package_name)
        if util.run_ok({"scp", "-i", getenv("LH_SSH_KEY_PATH"),
            "-P", getenv("LH_SSH_KEY_PORT"), package_filename, dest}) then
            print(string.format("Package %s uploaded successfully with version %s",
                package_name, package_version))
        else
            print(string.format("error uploading %s/%s into %s",
                package_version, package_name, LHELPER_WWW_DOMAIN))
        end
    else
        print(string.format(
            "Package %s with version %s already exists. No upload needed.",
            package_name, package_version))
    end
end

-------------------------------------------------------------------------------
-- misc helpers

local function fs_security_delay()
    -- Sometimes on windows we get an error when running tar:
    -- tar: <some-file>: file changed as we read it
    -- so we add an artificial delay to try to avoid the problem.
    if util.is_windows then
        util.spawn({"sleep", "1"})
    end
end

local function set_prefix_variables(prefix_dir)
    util.setenv("INSTALL_PREFIX", prefix_dir)
    local win_prefix = prefix_dir
    if util.is_windows then
        win_prefix = prefix_dir:gsub("^/c/", "c:/")
    end
    util.setenv("WIN_INSTALL_PREFIX", win_prefix)
end

local function prepare_temp_dir(base_dir)
    local temp_dir = base_dir .. "/tmp"
    util.rm_rf(temp_dir)
    util.mkdir_p(temp_dir)
end

-- The configuration of the active environment, from its lhelper-config
-- file (the user may have edited it).
local function active_env_config()
    return env.parse_config(getenv("LHELPER_ENV_PREFIX") .. "/bin/lhelper-config")
end

-- Re-apply the environment's compiler configuration as environment
-- variables. Needed because the recipes may modify CC, CFLAGS and the
-- other variables.
local function apply_env_config(config)
    for name, value in pairs(config) do
        util.setenv(name, value)
    end
end

-- Relocate prefix path references for all files in a library install's
-- directory. Returns the list of files that could not be relocated.
local function library_dir_reloc(archive_dir, old_prefix, new_prefix)
    local warning_files = {}
    for _, rel in ipairs(util.walk_files(archive_dir)) do
        local name = archive_dir .. "/" .. rel
        -- wxwidgets installs config files in the directory lib/wx/config so
        -- the pattern "/config/" matches these files
        if util.ends_with(name, ".pc") or util.ends_with(name, "-config") or
            name:find("/config/", 1, true) or util.ends_with(name, ".la") then
            if not pathreplace.replace(name, old_prefix, new_prefix) then
                warning_files[#warning_files + 1] = name
            end
        end
    end
    return warning_files
end

-- Extract a library package archive, relocate the prefix path references
-- and copy the files into the environment, writing the file list.
local function extract_archive_reloc(tar_package_filename, old_prefix, new_prefix,
        install_prefix, filename_list)
    local working_dir = getenv("LHELPER_WORKING_DIR")
    prepare_temp_dir(working_dir)
    local package_temp_dir = working_dir .. "/tmp"
    util.spawn({"tar", "-C", package_temp_dir, "-xf",
        package_dir() .. "/" .. tar_package_filename})
    library_dir_reloc(package_temp_dir, old_prefix, new_prefix)
    -- Write the list of the package's files (like "find ." would)
    local list_lines = { "." }
    for _, rel in ipairs(util.walk_all(package_temp_dir)) do
        list_lines[#list_lines + 1] = "./" .. rel
    end
    util.write_lines(filename_list, list_lines)
    -- Copy files in the destination directory
    util.spawn({"cp", "-a", package_temp_dir .. "/.", install_prefix})
end

local function fix_pkgconfig_install()
    local libdir = getenv("LHELPER_LIBDIR")
    local install_prefix = getenv("INSTALL_PREFIX")
    local found_pkgconfig
    if libdir ~= "lib" and util.is_dir(install_prefix .. "/lib/pkgconfig") then
        found_pkgconfig = "lib/pkgconfig"
    end
    if libdir ~= "lib" and util.is_dir(install_prefix .. "/share/pkgconfig") then
        found_pkgconfig = "share/pkgconfig"
    end
    if found_pkgconfig then
        print(string.format("Moving pkgconfig directory from \"%s\" to \"%s\"",
            util.dirname(found_pkgconfig), libdir))
        util.mkdir_p(install_prefix .. "/" .. libdir .. "/pkgconfig")
        util.spawn({"mv", install_prefix .. "/" .. found_pkgconfig,
            install_prefix .. "/" .. libdir})
        util.remove_empty_dirs(install_prefix .. "/" ..
            util.dirname(found_pkgconfig))
    end
end

-------------------------------------------------------------------------------
-- dependencies

-- Check a package's declared dependencies against a package registry
-- (a list of registry lines) and the system libraries. Returns the list
-- of missing dependencies.
local function check_dependencies(dependencies, registry_lines)
    local missing = {}
    for _, dependency in ipairs(dependencies) do
        if not util.starts_with(dependency, "?") then
            local dep_name = dependency:match("^%S+")
            local found = pkg.query_lines(registry_lines, dep_name)
            if found then
                local rc = pkg.test_package_spec(dependency, found)
                if rc == 1 then
                    print("Error: internal error, package name mismatch.")
                    os.exit(1)
                elseif rc == 2 then
                    print("Error: options for installed package " .. dep_name ..
                        " does not match.")
                    os.exit(1)
                elseif rc == 3 then
                    print("Error: incompatible version for installed package " ..
                        dep_name .. ".")
                    os.exit(1)
                elseif rc == 100 then
                    print("Error: Invalid package spec: \"" .. dependency .. "\"")
                    os.exit(1)
                end
                -- otherwise the package is already installed: do nothing
            else
                local sys_version = pkg.system_library_version(dep_name)
                if sys_version then
                    local entry = dep_name .. " " .. sys_version
                    if pkg.test_package_spec(dependency, entry, true) ~= 0 then
                        print("Error: incompatible version for system library " ..
                            dep_name .. ".")
                        os.exit(1)
                    end
                    -- Using system library
                else
                    missing[#missing + 1] = dependency
                end
            end
        end
    end
    return missing
end

-- Compute the list of the packages used by a package: its declared
-- dependencies resolved against the registry lines and the system
-- libraries, with the actual version used.
local function compute_package_list(dependencies, registry_lines)
    local usage = {}
    for _, dependency in ipairs(dependencies) do
        local name = dependency:match("^%S+"):gsub("^%?", "")
        if pkg.query_lines(registry_lines, name) then
            local entry = pkg.query_lines(registry_lines, name, true)
            if not util.contains(usage, entry) then
                usage[#usage + 1] = entry
            end
        else
            local sys_version = pkg.system_library_version(name)
            if sys_version then
                usage[#usage + 1] = name .. "[system] " .. sys_version
            else
                usage[#usage + 1] = name .. "[not-found]"
            end
        end
    end
    return usage
end

-------------------------------------------------------------------------------
-- environment digest

local function machine_type()
    local machine = util.trim(util.capture({"uname", "-m"}))
    local system = util.trim(util.capture({"uname", "-s"}))
    return machine .. "-" .. system:lower()
end

local function digest_content(config, usage_lines)
    local lines = {
        'CC="' .. (config.CC_BARE or "") .. '"',
        'CXX="' .. (config.CXX_BARE or "") .. '"',
        'CFLAGS="' .. (config.CFLAGS or "") .. '"',
        'CXXFLAGS="' .. (config.CXXFLAGS or "") .. '"',
        'LDFLAGS="' .. (config.LDFLAGS or "") .. '"',
        'BUILD_TYPE="' .. (config.BUILD_TYPE or "") .. '"',
        'MACHTYPE="' .. machine_type() .. '"',
        'CPU_TYPE="' .. (config.CPU_TYPE or "") .. '"',
        'CPU_TARGET="' .. (config.CPU_TARGET or "") .. '"',
        'CC_VERSION="' .. env.get_compiler_version(config.CC_BARE or "cc") .. '"',
        'CXX_VERSION="' .. env.get_compiler_version(config.CXX_BARE or "c++") .. '"',
        'OS_VERSION="' .. env.find_os_release() .. '"',
        '# dependencies',
    }
    util.append_all(lines, usage_lines)
    return table.concat(lines, "\n") .. "\n"
end

-- Compute the digest identifying the build environment of a package.
local function build_env_digest(config, usage_lines)
    local content = digest_content(config, usage_lines)
    local digest = md5.sumhexa(content)
    local digest_filename = getenv("LHELPER_WORKING_DIR") .. "/digests/" .. digest
    if not util.is_file(digest_filename) then
        util.write_file(digest_filename, content)
    end
    return digest
end

-------------------------------------------------------------------------------
-- library install

-- Parse the install arguments: <package> [options] [version].
-- Returns a table {package=, version=, options=, package_prefix=}.
local function parse_install_args(args)
    local spec = { options = {} }
    spec.package = args[1]
    spec.package_prefix = getenv("LHELPER_SYSTEM_PREFIX")
    for i = 2, #args do
        local a = args[i]
        if util.starts_with(a, "-") then
            spec.options[#spec.options + 1] = a
            local prefix_opt = a:match("^%-prefix=(.*)$")
            if prefix_opt then
                if prefix_opt == "" then os.exit(1) end
                spec.package_prefix = prefix_opt
            end
        else
            if spec.version then
                print(string.format("Unrecognized package argument \"%s\"", a))
                os.exit(1)
            end
            spec.version = a
        end
    end
    table.sort(spec.options)
    return spec
end

-- Find the recipe for a package spec and resolve the version when not
-- given. Fills spec.version and returns recipe_dir, recipe_filename,
-- recipe_version.
local function resolve_recipe(flags, spec)
    if flags.local_recipe and not spec.version then
        print("error: version is required for local recipes")
        os.exit(1)
    end
    if not spec.version then
        spec.version = installer.latest_package_version(spec.package)
        if not spec.version then
            print(string.format("error: cannot find package \"%s\"", spec.package))
            os.exit(1)
        end
    end
    local recipe_dir = flags.local_recipe and "." or installer.recipes_dir()
    local recipe_filename = installer.find_recipe_filename(recipe_dir,
        spec.package, spec.version)
    if not recipe_filename then
        print(string.format("error: no recipe found for \"%s\" version %s.",
            spec.package, spec.version))
        os.exit(1)
    end
    local recipe_version = recipe_filename:gsub("^" ..
        util.pattern_escape(spec.package .. "_"), ""):gsub("%.lua$", "")
    return recipe_dir, recipe_filename, recipe_version
end

-- "<name> [options] <recipe-version> <digest>"
local function make_package_line(spec, recipe_version, digest)
    local coll = { spec.package }
    util.append_all(coll, spec.options)
    coll[#coll + 1] = recipe_version
    coll[#coll + 1] = digest
    return table.concat(coll, " ")
end

local function recipe_error_report(code, err_msg, package, log_dirname, log_prefix)
    local stderr_log = log_dirname .. "/" .. log_prefix .. package .. "-stderr.log"
    if code == 3 then
        print("Some of the required commands for " .. package .. " is missing:")
        print("")
        io.write(util.read_file(stderr_log) or "")
        if err_msg then print(err_msg) end
    elseif code == 4 then
        print("error: package install was interruped.")
    elseif code == 5 then
        print("Error downloading the source code for " .. package .. ":")
        print("")
        io.write(util.read_file(stderr_log) or "")
        if err_msg then print(err_msg) end
    elseif code == 6 then
        print("Error while building the source code for " .. package .. ":")
        print("")
        io.write(util.read_file(stderr_log) or "")
        if err_msg then print(err_msg) end
    elseif code == 7 then
        print("Error in the configuration for " .. package .. ":")
        print("")
        io.write(util.read_file(stderr_log) or "")
        if err_msg then print(err_msg) end
    else
        if err_msg then print(err_msg) end
        print("error: building library \"" .. package .. "\"")
        print("    You may inspect the log files:")
        print("")
        print("    " .. log_prefix .. package .. "-stdout.log")
        print("    " .. log_prefix .. package .. "-stderr.log")
        print("")
        print("    located in the directory " .. log_dirname)
    end
    os.exit(1)
end

-- Run the "dependencies" phase of a recipe: returns the declared
-- dependencies and virtual packages, {dependencies = ..., provides = ...}.
local function run_dependencies_phase(recipe_dir, recipe_filename, spec,
        log_dirname, log_prefix)
    util.mkdir_p(getenv("LHELPER_TMPDIR") .. "/build")
    local ctx = {
        mode = "dependencies",
        package = spec.package,
        version = spec.version,
        options = spec.options,
        log_stdout = log_dirname .. "/" .. log_prefix .. spec.package .. "-stdout.log",
        log_stderr = log_dirname .. "/" .. log_prefix .. spec.package .. "-stderr.log",
    }
    util.write_file(ctx.log_stdout, "")
    util.write_file(ctx.log_stderr, "")
    local deps, code, err_msg = recipe.run_recipe(
        recipe_dir .. "/" .. recipe_filename, ctx)
    if not deps then
        recipe_error_report(code, err_msg, spec.package, log_dirname, log_prefix)
    end
    return deps
end

-- Install a library in the active environment. run_mode is "dependencies"
-- or "run". flags: {local_recipe=, rebuild=};
-- args: {package, [version], [options...]}.
-- In "dependencies" mode returns the missing dependencies and the recipe's
-- declarations; in "run" mode the declarations, obtained from a previous
-- "dependencies" call, are passed as the deps argument.
function installer.library_install(run_mode, flags, args, deps)
    flags = flags or {}
    local spec = parse_install_args(args)
    local package = spec.package
    local recipe_dir, recipe_filename, recipe_version = resolve_recipe(flags, spec)

    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    local log_dirname = env_prefix .. "/logs"
    local config = active_env_config()
    apply_env_config(config)
    util.setenv("package", package)
    util.setenv("version", spec.version)

    if run_mode == "dependencies" then
        local recipe_deps = run_dependencies_phase(recipe_dir, recipe_filename,
            spec, log_dirname, "deps-")
        local missing = check_dependencies(recipe_deps.dependencies,
            pkg.registry_lines(env_prefix))
        return missing, recipe_deps
    end

    deps = deps or { dependencies = {}, provides = {} }

    local options_tag = ""
    if #spec.options > 0 then
        options_tag = table.concat(spec.options, ""):gsub("^%-", "_")
    end

    if #spec.options == 0 then
        msg("Using recipe version " .. recipe_version)
    else
        msg("Using recipe version " .. recipe_version ..
            " with options: " .. table.concat(spec.options, " "))
    end
    if pkg.is_installed(env_prefix, package) then
        pkg.remove_package_files(env_prefix, package)
        msg("Removed previously installed package \"" .. package .. "\"")
    end

    -- Ensure that the temporary build directory exists
    util.mkdir_p(getenv("LHELPER_TMPDIR") .. "/build")

    local temp_root = getenv("LHELPER_WORKING_DIR") .. "/tmp"
    set_prefix_variables(temp_root)
    util.setenv("CONFIG_PREFIX", spec.package_prefix)

    local usage_lines = compute_package_list(deps.dependencies,
        pkg.registry_lines(env_prefix))
    local digest = build_env_digest(config, usage_lines)
    local package_line = make_package_line(spec, recipe_version, digest)

    if installer.show_dependencies then
        if #usage_lines > 0 then
            msg("The package dependencies are:")
            print("")
            for _, line in ipairs(usage_lines) do
                msg("* " .. line)
            end
            msg("")
        else
            msg("The package has no dependencies.")
        end
    end

    local tar_package_filename = string.format("%s%s_%s_%s.tar.gz",
        package, options_tag, recipe_version, digest)
    local can_use_saved = not flags.rebuild and not flags.local_recipe and
        not util.starts_with(spec.version, "git-")
    if can_use_saved and util.is_file(package_dir() .. "/" .. tar_package_filename) then
        msg("Found an existing package")
    elseif can_use_saved and
        check_remote_package(getenv("LHELPER_PACKAGE_VERSION"), tar_package_filename) then
        msg("Found an package in the remote location " .. LHELPER_WWW_DOMAIN)
        if not download_package(getenv("LHELPER_PACKAGE_VERSION"),
            tar_package_filename, getenv("LHELPER_WORKING_DIR") .. "/packages") then
            print("error: downloading package " .. tar_package_filename ..
                " from " .. LHELPER_WWW_DOMAIN)
            os.exit(1)
        end
    else
        prepare_temp_dir(getenv("LHELPER_WORKING_DIR"))
        msg("Building library...")

        -- Execute the recipe
        local recipe_ctx = {
            mode = "run",
            package = package,
            version = spec.version,
            options = spec.options,
            log_stdout = log_dirname .. "/" .. package .. "-stdout.log",
            log_stderr = log_dirname .. "/" .. package .. "-stderr.log",
        }
        util.write_file(recipe_ctx.log_stdout, "")
        util.write_file(recipe_ctx.log_stderr, "")
        local ok, code, err_msg = recipe.run_recipe(
            recipe_dir .. "/" .. recipe_filename, recipe_ctx)
        if not ok then
            recipe_error_report(code, err_msg, package, log_dirname, "")
        end
        fix_pkgconfig_install()
        msg("done")

        local warning_files = library_dir_reloc(temp_root,
            spec.package_prefix, "__LHELPER_PREFIX__")
        if #warning_files > 0 then
            io.stderr:write("warning: prefix directory \"" .. spec.package_prefix ..
                "\" found in binary files:\n\n")
            for _, warn_filename in ipairs(warning_files) do
                io.stderr:write(warn_filename .. "\n")
            end
            io.stderr:write("\nThe build recipe for this package may need to be fixed\n\n")
        end
        fs_security_delay()
        -- Create the archive outside of temp_root to avoid adding the
        -- archive to itself.
        local staging_tar = getenv("LHELPER_WORKING_DIR") .. "/" .. tar_package_filename
        if util.spawn({"tar", "-C", temp_root, "-czf", staging_tar, "."}) ~= 0 then
            print("error: cannot create the package archive for \"" .. package .. "\"")
            os.exit(1)
        end
        if getenv("LH_SSH_KEY_PATH") ~= "" and getenv("LH_SSH_KEY_PORT") ~= "" and
            not flags.local_recipe then
            upload_package(getenv("LHELPER_PACKAGE_VERSION"), staging_tar)
        end
        os.rename(staging_tar, package_dir() .. "/" .. tar_package_filename)
        print("Saved package for \"" .. package .. "\"")
    end

    set_prefix_variables(env_prefix)
    local filename_list = pkg.package_list_filename(env_prefix, package)
    extract_archive_reloc(tar_package_filename, "__LHELPER_PREFIX__",
        getenv("WIN_INSTALL_PREFIX"), getenv("INSTALL_PREFIX"), filename_list)
    pkg.register_package(env_prefix, package_line, deps.provides)
    msg("Package \"" .. package .. "\" successfully installed")
end

-- Get the package dependencies first and stop if some of them are missing,
-- then install the package.
function installer.library_check_and_install(flags, args)
    local missing, deps = installer.library_install("dependencies", flags, args)
    if #missing > 0 then
        print("Found missing packages:")
        print("")
        for _, line in ipairs(missing) do
            print("- " .. line)
        end
        print("")
        print("The package " .. args[1] .. " cannot be installed due to missing dependencies.")
        os.exit(1)
    end
    msg("Installing the requested package: " .. table.concat(args, " "))
    installer.library_install("run", flags, args, deps)
end

function installer.library_remove(package)
    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    if not pkg.is_installed(env_prefix, package) then
        print("package \"" .. package .. "\" not installed")
        os.exit(1)
    end
    pkg.remove_package_files(env_prefix, package)
    pkg.unregister_package(env_prefix, package)
    print("Package \"" .. package .. "\" successfully removed.")
end

-------------------------------------------------------------------------------
-- desired environment state

-- Compute in memory the registry lines an environment should have for a
-- build spec: for each package of the spec, run the recipe's dependencies
-- phase and compute the package's digest, resolving the dependencies
-- against the packages appearing earlier in the spec. No environment is
-- touched or created. Returns the registry lines.
function installer.compute_desired_packages(build_spec)
    local ok, err = env.compute_cpu_flags(build_spec)
    if not ok then
        print("error: " .. err)
        os.exit(1)
    end
    local config = env.spec_config(build_spec)

    -- The recipes' dependencies phase runs with the spec's compiler
    -- configuration in the environment, in isolation (like a subshell).
    local restore_env = util.env_snapshot()
    apply_env_config(config)

    local log_dirname = getenv("LHELPER_TMPDIR")
    local registry_lines = {}
    for _, package_spec in ipairs(build_spec.packages) do
        local spec = parse_install_args(util.split(package_spec))
        local recipe_dir, recipe_filename, recipe_version = resolve_recipe({}, spec)
        local deps = run_dependencies_phase(recipe_dir, recipe_filename, spec,
            log_dirname, "deps-")
        local missing = check_dependencies(deps.dependencies, registry_lines)
        if #missing > 0 then
            print("Found missing packages:")
            print("")
            for _, line in ipairs(missing) do
                print("- " .. line)
            end
            print("")
            print("The package " .. spec.package ..
                " cannot be installed due to missing dependencies.")
            os.exit(1)
        end
        local usage_lines = compute_package_list(deps.dependencies, registry_lines)
        local digest = build_env_digest(config, usage_lines)
        local package_line = make_package_line(spec, recipe_version, digest)
        pkg.lines_add(registry_lines, package_line)
        for _, provide_spec in ipairs(deps.provides) do
            registry_lines[#registry_lines + 1] = provide_spec .. " : " .. package_line
        end
    end

    restore_env()
    return registry_lines
end

-------------------------------------------------------------------------------
-- environment package list update

-- Turn a package line from the lhelper-packages file into the install
-- arguments for the same package: remove the recipe revision after "+" in
-- the version and discard the digest.
local function package_of_line(line)
    local words = util.split(line)
    local args = { words[1] }
    for i = 2, #words - 1 do
        local w = words[i]
        if i == #words - 1 then
            w = w:gsub("%+.*$", "")
        end
        args[#args + 1] = w
    end
    return args
end

-- Update the list of packages of the currently activated environment to
-- match the desired registry lines (new_list).
function installer.update_installed_packages(new_list)
    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    local packages_filename = env_prefix .. "/bin/lhelper-packages"

    -- old_list is the list of the currently installed packages, new_list is
    -- the list we want to have. We remove or install packages so that we
    -- match the new list.
    local old_list = util.read_lines(packages_filename)

    fs_security_delay()
    util.write_file(packages_filename, "")
    local out = assert(io.open(packages_filename, "a"))

    local newly_installed_packages = {}
    local function skip_removal(line)
        local name = line:match("^%S+")
        return util.contains(newly_installed_packages, name)
    end

    local i, j = 1, 1
    local n, m = #new_list, #old_list
    while i <= n do
        if new_list[i] == old_list[j] then
            -- lines match: write the line in lhelper-packages and move on
            out:write(new_list[i], "\n")
            out:flush()
            i = i + 1
            j = j + 1
        else
            -- entries do not match: look if the new_list entry is present
            -- in old_list but later
            local k, found = j + 1, false
            while k <= m do
                if new_list[i] == old_list[k] then
                    found = true
                    break
                end
                k = k + 1
            end
            if found then
                -- remove all the old_list entries up to the matching one
                while j < k do
                    if not skip_removal(old_list[j]) and
                        not old_list[j]:find(" : ", 1, true) then
                        pkg.remove_package_files(env_prefix, old_list[j]:match("^%S+"))
                    end
                    j = j + 1
                end
            else
                -- The new_list entry is not found: install it.
                -- NOTE: it adds one or more lines in the lhelper-packages
                -- file (more than one if the package "provides" some
                -- virtual packages).
                if not new_list[i]:find(" : ", 1, true) then
                    newly_installed_packages[#newly_installed_packages + 1] =
                        new_list[i]:match("^%S+")
                    out:close()
                    installer.library_check_and_install({},
                        package_of_line(new_list[i]))
                    out = assert(io.open(packages_filename, "a"))
                end
                i = i + 1
            end
        end
    end
    out:close()
    -- Remove any remaining package not present in the new list. Skip the
    -- packages just installed: they may have been reinstalled above with
    -- different options and we don't want to remove the new files.
    while j <= m do
        if not skip_removal(old_list[j]) and
            not old_list[j]:find(" : ", 1, true) then
            pkg.remove_package_files(env_prefix, old_list[j]:match("^%S+"))
        end
        j = j + 1
    end
end

-- Check that the environment activate script was created from the current
-- working directory.
local function check_env_root_match(env_source)
    for _, line in ipairs(util.read_lines(env_source)) do
        local root = line:match('^export LHELPER_ENV_ROOT="(.*)"%s*$')
        if root then
            return root == lhsys.getcwd()
        end
    end
    return false
end

-- Load the environment with the given name only if its configuration
-- matches the build spec. When it matches the environment is activated
-- in-process and its package list updated to the desired one; returns
-- true. Returns false otherwise.
function installer.load_matching_env(env_name, env_workdir, build_spec)
    local env_prefix = env_workdir .. "/" .. env_name
    local env_source = env_prefix .. "/bin/activate"

    local desired_lines = installer.compute_desired_packages(build_spec)
    local desired_config = env.config_content(build_spec)

    if util.is_dir(env_prefix) and
        util.read_file(env_prefix .. "/bin/lhelper-config") == desired_config and
        check_env_root_match(env_source) then
        env.activate_in_process(env_prefix, lhsys.getcwd(), env_name)
        installer.update_installed_packages(desired_lines)
        return true
    end
    return false
end

return installer
