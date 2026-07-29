-- Package install orchestration: run recipes, package the build results,
-- install them into an environment and keep the environment's package list
-- up to date.
--
-- The unit of work is the install plan: for each requested package the
-- recipe's "dependencies" phase runs once and everything the install needs
-- is computed up front — recipe location, declared dependencies, resolved
-- usage lines, build environment digest and registry line. The plans are
-- then executed, reusing a saved or remote package archive when possible,
-- and the registry lines written into the environment are the planned ones,
-- so the environment always converges to the computed state. The only files
-- used are the persistent ones: the lhelper-packages registry, the
-- per-package .list files, the archives/packages caches and the build logs.
--
-- The requested packages do not need to list their dependencies: the
-- dependencies that are not explicitly requested and are provided neither
-- by the environment nor by a system library are added to the plans, before
-- the package requiring them (see resolve_install_plans).

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

-- The options, the words starting with "-", of a package spec or of a
-- registry line.
local function spec_options(line)
    local options = {}
    for _, word in ipairs(util.split(line)) do
        if util.starts_with(word, "-") then
            options[#options + 1] = word
        end
    end
    return options
end

-- Add to a list of options the ones not already present.
local function add_options(list, options)
    for _, option in ipairs(options) do
        if not util.contains(list, option) then
            list[#list + 1] = option
        end
    end
    return list
end

-- Report a dependency spec that the package entry found does not satisfy
-- and exit. The code rc is the one returned by pkg.test_package_spec.
local function report_dependency_error(rc, dependency, entry)
    local dep_name = dependency:match("^%S+")
    if rc == 1 then
        print("Error: internal error, package name mismatch.")
    elseif rc == 2 then
        print("Error: options for installed package \"" ..
            dep_name .. "\" do not match the required spec.\n" ..
            "  Required:  " .. dep_name .. " " ..
            table.concat(spec_options(dependency), " ") .. "\n" ..
            "  Installed: " .. dep_name .. " " ..
            table.concat(spec_options(entry), " "))
    elseif rc == 3 then
        print("Error: incompatible version for installed package " ..
            dep_name .. ".")
    else
        print("Error: Invalid package spec: \"" .. dependency .. "\"")
    end
    os.exit(1)
end

-- Check a package's declared dependency against a package registry (a list
-- of registry lines) and the system libraries. Returns "ok" when the
-- dependency is already satisfied, "missing" when no package provides it
-- or, when a package with that name does not satisfy the spec, "mismatch"
-- with the pkg.test_package_spec code and the registry entry found.
local function dependency_status(dependency, registry_lines)
    local dep_name = dependency:match("^%S+")
    local found = pkg.query_lines(registry_lines, dep_name)
    if found then
        local rc = pkg.test_package_spec(dependency, found)
        if rc ~= 0 then return "mismatch", rc, found end
        -- the package is already installed: do nothing
        return "ok"
    end
    local sys_version = pkg.system_library_version(dep_name)
    if sys_version then
        local entry = dep_name .. " " .. sys_version
        if pkg.test_package_spec(dependency, entry, true) ~= 0 then
            print("Error: incompatible version for system library " ..
                dep_name .. ".")
            os.exit(1)
        end
        -- Using system library
        return "ok"
    end
    return "missing"
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
-- recipe_version. When the package is installed to satisfy a dependency
-- required_by names the package requiring it, for the error messages.
local function resolve_recipe(flags, spec, required_by)
    local context = required_by and
        string.format(" (required by \"%s\")", required_by) or ""
    if flags.local_recipe and not spec.version then
        print("error: version is required for local recipes")
        os.exit(1)
    end
    if not spec.version then
        spec.version = installer.latest_package_version(spec.package)
        if not spec.version then
            print(string.format("error: cannot find package \"%s\"%s",
                spec.package, context))
            os.exit(1)
        end
    end
    local recipe_dir = flags.local_recipe and "." or installer.recipes_dir()
    local recipe_filename = installer.find_recipe_filename(recipe_dir,
        spec.package, spec.version)
    if not recipe_filename then
        print(string.format("error: no recipe found for \"%s\" version %s%s.",
            spec.package, spec.version, context))
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

-- Start the installation of a package: resolve the recipe and run its
-- "dependencies" phase, so that the packages it depends on are known. The
-- compiler configuration `config` is applied to the process environment
-- before running the recipe. Returns a partial install plan, to be
-- completed with complete_install_plan once the dependencies are resolved.
-- flags: {local_recipe=, rebuild=}; args: {package, [version], [options...]}.
local function begin_install_plan(flags, args, config, log_dirname, required_by)
    local spec = parse_install_args(args)
    local recipe_dir, recipe_filename, recipe_version =
        resolve_recipe(flags, spec, required_by)
    apply_env_config(config)
    util.setenv("package", spec.package)
    util.setenv("version", spec.version)
    local deps = run_dependencies_phase(recipe_dir, recipe_filename, spec,
        log_dirname, "deps-")
    return {
        flags = flags,
        args = args,
        spec = spec,
        recipe_dir = recipe_dir,
        recipe_filename = recipe_filename,
        recipe_version = recipe_version,
        deps = deps,
    }
end

-- Complete an install plan, once its dependencies are all satisfied by the
-- given registry lines, with everything else the install needs: the usage
-- lines, the build environment digest and the package's registry line.
local function complete_install_plan(plan, registry_lines, config)
    plan.usage_lines = compute_package_list(plan.deps.dependencies, registry_lines)
    plan.digest = build_env_digest(config, plan.usage_lines)
    plan.package_line = make_package_line(plan.spec, plan.recipe_version,
        plan.digest)
    return plan
end

-------------------------------------------------------------------------------
-- dependencies resolution

-- Maximum number of resolution passes: every pass but the first one is due
-- to an automatically added package that gained at least one option.
local RESOLVE_PASSES_LIMIT = 16

-- The install arguments for a dependency spec: the package name, the
-- options of the spec together with the extra options accumulated for the
-- package, and the version when the spec requires an exact one.
local function dependency_install_args(dependency, extra_options)
    local args = { dependency:match("^%S+") }
    local options = add_options(spec_options(dependency), extra_options or {})
    table.sort(options)
    util.append_all(args, options)
    for _, word in ipairs(util.split(dependency)) do
        local exact_version = word:match("^=(%S+)$")
        if exact_version then args[#args + 1] = exact_version end
    end
    return args
end

-- The package entry of a plan, "<name> [options] <version>", used to check
-- that the package satisfies the dependency specs requiring it.
local function plan_entry_line(plan)
    local coll = { plan.spec.package }
    util.append_all(coll, plan.spec.options)
    coll[#coll + 1] = plan.spec.version
    return table.concat(coll, " ")
end

-- Resolve the requested packages into an ordered list of install plans, in
-- a single pass. Each request is a table {args = ..., flags = ...}. The
-- dependencies satisfied neither by the registry lines nor by a system
-- library are added to the plans, before the package requiring them, with
-- the options of the dependency spec plus the ones accumulated for the
-- package in extra_options. An explicitly requested package is used, and
-- moved before the packages depending on it, in place of an automatically
-- added one. When an automatically added package turns out to need more
-- options than it was given the options are recorded in extra_options and
-- the pass is abandoned raising a {restart = true} error.
local function resolve_plans_pass(requested, registry_lines, config,
        log_dirname, extra_options)
    local explicit = {}
    for _, request in ipairs(requested) do
        explicit[request.args[1]] = request
    end
    local lines = util.append_all({}, registry_lines)
    local plans, planned, resolving, stack = {}, {}, {}, {}
    local resolve

    -- Satisfy a dependency of the package required_by, adding to the plans
    -- the package needed for it when there is none.
    local function satisfy(dependency, required_by)
        local dep_name = dependency:match("^%S+")
        local status, rc, entry = dependency_status(dependency, lines)
        if status == "ok" then return end
        if status == "mismatch" then
            local found = planned[dep_name]
            if rc == 2 and found and found.auto then
                -- The package was added automatically with too few options:
                -- accumulate the options of both packages requiring it and
                -- resolve everything again.
                local extra = extra_options[dep_name] or {}
                add_options(extra, spec_options(entry))
                add_options(extra, spec_options(dependency))
                extra_options[dep_name] = extra
                error({ restart = true }, 0)
            end
            report_dependency_error(rc, dependency, entry)
        end
        local request = explicit[dep_name]
        local plan = resolve(request or {
            args = dependency_install_args(dependency, extra_options[dep_name]),
        }, request == nil, required_by)
        -- The options of an automatically added package are the required
        -- ones by construction but its version, the latest one available,
        -- may not satisfy the dependency spec.
        local check = pkg.test_package_spec(dependency, plan_entry_line(plan))
        if check ~= 0 then
            if plan.auto then
                print(string.format("error: the available version %s of the " ..
                    "package \"%s\" does not satisfy the dependency \"%s\" of " ..
                    "the package \"%s\".", plan.spec.version, dep_name,
                    dependency, required_by))
                os.exit(1)
            end
            report_dependency_error(check, dependency, plan_entry_line(plan))
        end
    end

    -- Add a package to the plans, preceded by the packages needed by its
    -- dependencies. Returns the package's plan.
    resolve = function(request, auto, required_by)
        local name = request.args[1]
        if planned[name] then return planned[name] end
        if resolving[name] then
            print("error: dependency cycle for the package \"" .. name ..
                "\": " .. table.concat(stack, " -> ") .. " -> " .. name)
            os.exit(1)
        end
        resolving[name] = true
        stack[#stack + 1] = name
        local plan = begin_install_plan(request.flags or {}, request.args,
            config, log_dirname, auto and required_by or nil)
        plan.auto = auto
        plan.required_by = required_by
        for _, dependency in ipairs(plan.deps.dependencies) do
            if not util.starts_with(dependency, "?") then
                satisfy(dependency, name)
            end
        end
        resolving[name] = nil
        stack[#stack] = nil
        complete_install_plan(plan, lines, config)
        plans[#plans + 1] = plan
        planned[name] = plan
        pkg.lines_add(lines, plan.package_line)
        for _, provide_spec in ipairs(plan.deps.provides) do
            lines[#lines + 1] = provide_spec .. " : " .. plan.package_line
        end
        return plan
    end

    for _, request in ipairs(requested) do
        resolve(request, false)
    end
    return plans
end

-- Resolve the requested packages, {args = ..., flags = ...} tables, into an
-- ordered list of install plans including the packages needed to satisfy
-- the dependencies missing from the registry lines. The resolution is
-- repeated as long as the options of an automatically added package need to
-- be extended.
local function resolve_install_plans(requested, registry_lines, config, log_dirname)
    local extra_options = {}
    for _ = 1, RESOLVE_PASSES_LIMIT do
        local ok, result = pcall(resolve_plans_pass, requested, registry_lines,
            config, log_dirname, extra_options)
        if ok then return result end
        if not (type(result) == "table" and result.restart) then
            error(result, 0)
        end
    end
    print("error: cannot resolve the packages dependencies, giving up after " ..
        RESOLVE_PASSES_LIMIT .. " attempts.")
    os.exit(1)
end

-- Report the packages that were added to satisfy the dependencies.
local function report_added_packages(plans)
    local added = {}
    for _, plan in ipairs(plans) do
        if plan.auto then added[#added + 1] = plan end
    end
    if #added == 0 then return end
    msg("Packages added to satisfy the dependencies:")
    msg("")
    for _, plan in ipairs(added) do
        msg(string.format("* %s (required by %s)",
            table.concat(plan.args, " "), plan.required_by))
    end
    msg("")
end

-- The message announcing the install of a package.
local function install_message(plan)
    if plan.auto then
        return "Installing the package \"" .. table.concat(plan.args, " ") ..
            "\" required by \"" .. plan.required_by .. "\""
    end
    return "Installing the requested package: " .. table.concat(plan.args, " ")
end

-- Execute an install plan in the active environment: reuse a saved or
-- remote package archive when available, otherwise build the package with
-- its recipe; then extract the files into the environment and register the
-- package. The digest and registry line are the planned ones, so what is
-- registered is exactly what was computed by prepare_install_plan.
local function execute_install_plan(plan)
    local flags, spec = plan.flags, plan.spec
    local package = spec.package
    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    local log_dirname = env_prefix .. "/logs"
    -- The recipes run so far may have modified CC, CFLAGS and the other
    -- variables: restart from the environment's configuration.
    apply_env_config(active_env_config())
    util.setenv("package", package)
    util.setenv("version", spec.version)

    local options_tag = ""
    if #spec.options > 0 then
        options_tag = table.concat(spec.options, ""):gsub("^%-", "_")
    end

    if #spec.options == 0 then
        msg("Using recipe version " .. plan.recipe_version)
    else
        msg("Using recipe version " .. plan.recipe_version ..
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

    if installer.show_dependencies then
        if #plan.usage_lines > 0 then
            msg("The package dependencies are:")
            print("")
            for _, line in ipairs(plan.usage_lines) do
                msg("* " .. line)
            end
            msg("")
        else
            msg("The package has no dependencies.")
        end
    end

    local tar_package_filename = string.format("%s%s_%s_%s.tar.gz",
        package, options_tag, plan.recipe_version, plan.digest)
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
            plan.recipe_dir .. "/" .. plan.recipe_filename, recipe_ctx)
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
    pkg.register_package(env_prefix, plan.package_line, plan.deps.provides)
    msg("Package \"" .. package .. "\" successfully installed")
end

-- Prepare the install plan of a package against the active environment,
-- with the plans of the dependencies the environment does not provide,
-- then install them all.
function installer.library_check_and_install(flags, args)
    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    local plans = resolve_install_plans({ { args = args, flags = flags } },
        pkg.registry_lines(env_prefix), active_env_config(),
        env_prefix .. "/logs")
    report_added_packages(plans)
    for _, plan in ipairs(plans) do
        msg(install_message(plan))
        execute_install_plan(plan)
    end
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

-- Compute the install plans for the packages of a build spec: for each
-- package of the spec, and for each package added to satisfy a dependency,
-- run the recipe's dependencies phase and compute the package's digest and
-- registry line. The plans are ordered so that every package comes after
-- the ones it depends on. No environment is touched or created. Exits when
-- some dependencies cannot be satisfied.
local function compute_install_plans(build_spec)
    local ok, err = env.compute_cpu_flags(build_spec)
    if not ok then
        print("error: " .. err)
        os.exit(1)
    end
    local config = env.spec_config(build_spec)

    -- The recipes' dependencies phase runs with the spec's compiler
    -- configuration in the environment, in isolation (like a subshell).
    local restore_env = util.env_snapshot()

    local log_dirname = getenv("LHELPER_TMPDIR")
    local requested = {}
    for _, package_spec in ipairs(build_spec.packages) do
        requested[#requested + 1] = { args = util.split(package_spec), flags = {} }
    end
    local plans = resolve_install_plans(requested, {}, config, log_dirname)

    restore_env()
    report_added_packages(plans)
    return plans
end

-------------------------------------------------------------------------------
-- environment package list update

-- Update the currently activated environment to match the given install
-- plans: remove the files of the packages whose registry line is no longer
-- desired, install the packages not already present and rebuild the
-- lhelper-packages registry in the plans' order.
function installer.update_installed_packages(plans)
    local env_prefix = getenv("LHELPER_ENV_PREFIX")
    local packages_filename = env_prefix .. "/bin/lhelper-packages"
    local old_lines = util.read_lines(packages_filename)

    local desired = {}
    for _, plan in ipairs(plans) do
        desired[plan.package_line] = true
    end
    -- Remove the files of the packages that are not in the desired state;
    -- the packages whose registry line changed are reinstalled below.
    local kept = {}
    for _, line in ipairs(old_lines) do
        if not line:find(" : ", 1, true) then
            if desired[line] then
                kept[line] = true
            else
                pkg.remove_package_files(env_prefix, line:match("^%S+"))
            end
        end
    end

    fs_security_delay()
    util.write_file(packages_filename, "")
    for _, plan in ipairs(plans) do
        if kept[plan.package_line] then
            -- already installed and unchanged: keep the files and
            -- re-register the package and its virtual packages
            pkg.register_package(env_prefix, plan.package_line,
                plan.deps.provides)
        else
            msg(install_message(plan))
            execute_install_plan(plan)
        end
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
-- in-process and its packages updated to the spec's install plans; returns
-- true. Returns false otherwise. The computed plans are returned as the
-- second value, so the caller can use them to populate a freshly created
-- environment when no matching one was found.
function installer.load_matching_env(env_name, env_workdir, build_spec)
    local env_prefix = env_workdir .. "/" .. env_name
    local env_source = env_prefix .. "/bin/activate"

    local plans = compute_install_plans(build_spec)
    local desired_config = env.config_content(build_spec)

    if util.is_dir(env_prefix) and
        util.read_file(env_prefix .. "/bin/lhelper-config") == desired_config and
        check_env_root_match(env_source) then
        env.activate_in_process(env_prefix, lhsys.getcwd(), env_name)
        installer.update_installed_packages(plans)
        return true, plans
    end
    return false, plans
end

return installer
