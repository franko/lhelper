-- Recipe API and recipe runner.
--
-- A recipe is a Lua file run in an environment providing the functions
-- below (enter_archive, build_and_install, dependency, ...) plus the
-- variables: version, options, platform, cpu_type, cpu_target, build_type.
--
-- Each recipe is run in two phases: a "dependencies" phase where the
-- download/build functions do nothing and dependency()/provides() record
-- their information, and a "run" phase performing the actual build.
--
-- Error exit codes (matching the original bash implementation):
-- 3 missing command, 4 interrupted, 5 download error, 6 build error,
-- 7 recipe configuration error.

local util = require "util"
local lhsys = require "lhsys"
local pkg = require "pkg"

local recipe = {}

local skip_pic_option = util.is_windows

-------------------------------------------------------------------------------
-- helpers

local function getenv_or(name, default)
    local value = os.getenv(name)
    return (value and value ~= "") and value or default
end

-- get a suitable archive filename from a download URL
function recipe.archive_filename_of_url(url)
    -- Remove protocol (http://, https://, etc)
    local clean_url = url:gsub("^.-://", "")
    -- Split the URL at the last "/"
    local base_url, file_name = clean_url:match("^(.*)/([^/]*)$")
    if not base_url then
        base_url, file_name = "", clean_url
    end
    -- Replace special characters; in the base url '.' also gets replaced
    base_url = base_url:gsub("[^%w]", "_")
    file_name = file_name:gsub("[^%w.]", "_")
    local filename = base_url .. "_" .. file_name
    -- Remove uninformative parts from the url-now-a-filename
    filename = filename:gsub("www_", "")
    filename = filename:gsub("downloads_", "")
    filename = filename:gsub("download_", "")
    filename = filename:gsub("_archive_refs_tags_", "_")
    filename = filename:gsub("_releases_", "_")
    filename = filename:gsub("_release_", "_")
    return filename
end

-- Translate /usr to C:/msys64/usr, for example, but only on windows.
local function to_real_prefix(prefix)
    if util.is_windows and util.starts_with(prefix, "/") then
        local msysroot = os.getenv("LH_MSYSROOT")
        if msysroot and msysroot ~= "" then
            return msysroot .. prefix:sub(2)
        end
    end
    return prefix
end

local function get_prefix_rel(prefix)
    -- remove the leading drive letter, for Windows, if present
    local rel = prefix:gsub("^%a:", "")
    rel = rel:gsub("^/", "")
    -- Remove a possible trailing "/": it can happen when the prefix is
    -- the root directory itself.
    rel = rel:gsub("/$", "")
    return rel
end

-- Inside destdir move the files from destdir/prefix into the destdir root.
-- Explanation: when using Meson and CMake with DESTDIR the files are
-- installed in destdir + prefix. On Windows, in addition, a prefix like
-- /usr is translated to C:/msys64/usr.
local function normalize_destdir_install(destdir, setup_prefix, msys)
    if msys then
        setup_prefix = to_real_prefix(setup_prefix)
    end
    local prefix_rel = get_prefix_rel(setup_prefix)
    if prefix_rel == "" then return end
    local content_dir = prefix_rel:match("^([^/]*)")
    local source_dir = destdir .. "/" .. prefix_rel
    for _, name in ipairs(util.listdir(source_dir)) do
        -- FIXME: name may conflict with the dirname of prefix_rel
        os.rename(source_dir .. "/" .. name, destdir .. "/" .. name)
    end
    util.rm_rf(destdir .. "/" .. content_dir)
end

local function nproc()
    if util.which("nproc") then
        local output, code = util.capture({"nproc", "--all"})
        if code == 0 and util.trim(output) ~= "" then
            return util.trim(output)
        end
    elseif util.platform == "darwin" then
        local output, code = util.capture({"sysctl", "-n", "hw.ncpu"})
        if code == 0 and util.trim(output) ~= "" then
            return util.trim(output)
        end
    end
    return nil
end

-------------------------------------------------------------------------------
-- build system option translation

local function parse_common_build_options(args, on_option)
    local remainder = {}
    for _, a in ipairs(args) do
        if not on_option(a) then
            remainder[#remainder + 1] = a
        end
    end
    return remainder
end

-- configure-based build options. Returns options list, build type.
local function configure_options(args, build_type)
    local wxconfigure = false
    if args[1] == "--wxwidgets" then
        wxconfigure = true
        args = { table.unpack(args, 2) }
    end
    local prefix_val = os.getenv("LHELPER_SYSTEM_PREFIX")
    local use_shared, want_pic = false, false
    local options = parse_common_build_options(args, function(a)
        local prefix_opt = a:match("^%-prefix=(.*)$")
        local buildtype_opt = a:match("^%-%-buildtype=(.*)$")
        if prefix_opt then prefix_val = prefix_opt
        elseif a == "-shared" then use_shared = true
        elseif a == "-pic" then want_pic = true
        elseif buildtype_opt then build_type = buildtype_opt
        else return false end
        return true
    end)
    options[#options + 1] = "--prefix=" .. prefix_val
    if not wxconfigure then
        if use_shared then
            util.append_all(options, {"--enable-shared", "--disable-static"})
        else
            util.append_all(options, {"--disable-shared", "--enable-static"})
        end
        if want_pic and not skip_pic_option then
            options[#options + 1] = "--with-pic=yes"
        end
    else
        options[#options + 1] = use_shared and "--enable-shared" or "--disable-shared"
        if (want_pic or use_shared) and not skip_pic_option then
            options[#options + 1] = "--enable-pic"
        else
            options[#options + 1] = "--disable-pic"
        end
    end
    return options, build_type, prefix_val
end

local function meson_options(args)
    local prefix_val = os.getenv("LHELPER_SYSTEM_PREFIX")
    local shared_option = "static"
    local pic_option, build_flag
    local options = parse_common_build_options(args, function(a)
        local prefix_opt = a:match("^%-prefix=(.*)$")
        if prefix_opt then prefix_val = prefix_opt
        elseif a == "-shared" then shared_option = "shared"
        elseif a == "-pic" then
            if not skip_pic_option then pic_option = "true" end
        elseif a:match("^%-%-buildtype=") then build_flag = a
        else return false end
        return true
    end)
    if not build_flag then
        build_flag = "--buildtype=" .. os.getenv("BUILD_TYPE"):lower()
    end
    util.append_all(options, {"--prefix=" .. prefix_val, build_flag,
        "-Ddefault_library=" .. shared_option})
    if shared_option == "static" and pic_option then
        options[#options + 1] = "-Db_staticpic=" .. pic_option
    end
    return options, prefix_val
end

local function cmake_options(args)
    local prefix_val = os.getenv("LHELPER_SYSTEM_PREFIX")
    local pic_option, build_flag
    local shared_lib = "OFF"
    local options = parse_common_build_options(args, function(a)
        local prefix_opt = a:match("^%-prefix=(.*)$")
        local buildtype_opt = a:match("^%-%-buildtype=(.*)$")
        if prefix_opt then prefix_val = prefix_opt
        elseif a == "-pic" then
            if not skip_pic_option then pic_option = "ON" end
        elseif a == "-shared" then shared_lib = "ON"
        elseif buildtype_opt then build_flag = buildtype_opt
        else return false end
        return true
    end)
    if not build_flag then
        options[#options + 1] = "-DCMAKE_BUILD_TYPE=" .. os.getenv("BUILD_TYPE")
    elseif build_flag ~= "plain" then
        options[#options + 1] = "-DCMAKE_BUILD_TYPE=" ..
            build_flag:sub(1, 1):upper() .. build_flag:sub(2)
    end
    util.append_all(options, {"-DCMAKE_INSTALL_PREFIX=" .. prefix_val,
        "-DBUILD_SHARED_LIBS=" .. shared_lib})
    if pic_option then
        options[#options + 1] = "-DCMAKE_POSITION_INDEPENDENT_CODE=" .. pic_option
    end
    return options, prefix_val
end

-------------------------------------------------------------------------------
-- recipe runner

-- Create the recipe environment. ctx:
--   mode: "dependencies" or "run"
--   package, version, options (list of not-consumed arguments)
--   log_stdout, log_stderr: log file paths
function recipe.make_recipe_env(ctx)
    local R = {}
    local dependencies_mode = (ctx.mode == "dependencies")

    local log_out = io.open(ctx.log_stdout, "a")
    local log_err = io.open(ctx.log_stderr, "a")
    ctx.close_logs = function()
        log_out:close()
        log_err:close()
    end

    local function log_print(...)
        local parts = {}
        for _, v in ipairs({...}) do parts[#parts + 1] = tostring(v) end
        log_out:write(table.concat(parts, " "), "\n")
        log_out:flush()
    end

    local function log_error(...)
        local parts = {}
        for _, v in ipairs({...}) do parts[#parts + 1] = tostring(v) end
        log_err:write(table.concat(parts, " "), "\n")
        log_err:flush()
    end

    -- Run a command with the output sent to the recipe's log files.
    -- opts.on_error_code selects the lhelper exit code used on failure.
    local function log_run(argv, opts)
        opts = opts or {}
        log_out:flush()
        log_err:flush()
        local code = util.spawn(argv, { cwd = opts.cwd,
            stdout = ctx.log_stdout, stderr = ctx.log_stderr, append = true })
        if code ~= 0 and not opts.no_fail then
            util.fail(opts.on_error_code or 6,
                opts.error_message or
                    string.format("error: command \"%s\" failed", argv[1]))
        end
        return code
    end

    local build_root = os.getenv("LHELPER_TMPDIR") .. "/build"

    -- Removing a leftover build tree and moving the freshly extracted one into
    -- place must never fail quietly: the build would then run inside a stale,
    -- half-deleted directory and report something unrelated, like a missing
    -- ./configure script.
    local function remove_or_fail(path)
        local ok, err = util.rm_rf(path)
        if not ok then
            util.fail(1, "error: cannot remove \"" .. path .. "\": " .. tostring(err))
        end
    end

    local function rename_or_fail(from, to)
        local ok, err = os.rename(from, to)
        if not ok then
            util.fail(1, "error: cannot move \"" .. from .. "\" to \"" .. to ..
                "\": " .. tostring(err))
        end
    end

    local function enter_dummy_build_dir()
        util.rm_rf(build_root .. "/.tmp")
        util.mkdir_p(build_root .. "/.tmp")
        assert(lhsys.chdir(build_root .. "/.tmp"))
    end

    -- Extract an archive into the build directory and chdir into the
    -- top directory of the archive content.
    local function expand_enter_archive(path_filename, extract_options)
        local filename = util.basename(path_filename)
        assert(lhsys.chdir(build_root))
        local tmp_expand_dir = build_root .. "/.sas"
        util.rm_rf(tmp_expand_dir)
        util.mkdir_p(tmp_expand_dir)
        local cmd
        if filename:match("%.tar%.") or filename:match("%.tgz$") then
            cmd = {"tar", "xf", path_filename}
        elseif filename:match("%.zip$") then
            cmd = {"unzip", path_filename}
        else
            util.fail(1, string.format("error: unknown archive format: \"%s\"", filename))
        end
        util.append_all(cmd, extract_options or {})
        local code = util.spawn(cmd, { cwd = tmp_expand_dir,
            stdout = ctx.log_stdout, stderr = ctx.log_stderr, append = true })
        if code ~= 0 then
            util.fail(5, "Got invalid archive: " .. filename)
        end
        local entries = util.listdir(tmp_expand_dir)
        if #entries == 0 then
            util.fail(5, "error: empty archive " .. filename)
        end
        local topdir
        if #entries == 1 and util.is_dir(tmp_expand_dir .. "/" .. entries[1]) then
            topdir = entries[1]
            remove_or_fail(build_root .. "/" .. topdir)
            rename_or_fail(tmp_expand_dir .. "/" .. topdir,
                build_root .. "/" .. topdir)
        else
            -- archive without a top level directory: use the archive name
            topdir = filename:match("^([^.]*)")
            local xdest = build_root .. "/" .. topdir
            remove_or_fail(xdest)
            util.mkdir_p(xdest)
            for _, name in ipairs(entries) do
                rename_or_fail(tmp_expand_dir .. "/" .. name, xdest .. "/" .. name)
            end
        end
        util.rm_rf(tmp_expand_dir)
        assert(lhsys.chdir(build_root .. "/" .. topdir))
    end

    -- Wipe everything left in the build directory by a previous build. It is
    -- shared by every environment and is deliberately not cleaned at the end
    -- of a build, so that a failed build can still be inspected.
    local function clean_build_root()
        util.mkdir_p(build_root)
        for _, name in ipairs(util.listdir(build_root)) do
            remove_or_fail(build_root .. "/" .. name)
        end
    end

    -- Run a download step (curl or git clone) while catching Ctrl-C, so that
    -- an interrupted download does not leave a partial file behind in the
    -- archives cache. `cleanup_path` is the file or directory being written;
    -- if a SIGINT is received while `body` runs, it is removed and lhelper
    -- exits with the "interrupted" code (4). This mirrors the SIGINT trap the
    -- original bash implementation installed around curl and git clone.
    local function download_guarded(cleanup_path, body)
        lhsys.arm_interrupt()
        local results = { pcall(body) }
        lhsys.disarm_interrupt()
        if lhsys.interrupted() then
            if cleanup_path then
                log_print("cleaning up interrupted download \"" .. cleanup_path .. "\"")
                util.rm_rf(cleanup_path)
            end
            util.fail(4, "error: package install was interrupted")
        end
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2)
    end

    ---------------------------------------------------------------------------
    -- recipe API

    R.version = ctx.version
    R.options = ctx.options
    R.platform = util.platform
    R.cpu_type = os.getenv("CPU_TYPE")
    R.cpu_target = os.getenv("CPU_TARGET")
    R.build_type = os.getenv("BUILD_TYPE")
    R.print = log_print
    R.getenv = os.getenv

    function R.setenv(name, value)
        util.setenv(name, value)
    end

    function R.check_commands(...)
        if dependencies_mode then return end
        for _, command in ipairs({...}) do
            if not util.which(command) then
                util.fail(3, string.format(
                    "error: command \"%s\" is required but it's not available", command))
            end
        end
    end

    function R.test_commands(...)
        for _, command in ipairs({...}) do
            if not util.which(command) then
                log_error(string.format(
                    "error: command \"%s\" is required but it's not available", command))
                return false
            end
        end
        return true
    end

    -- dependency("sdl2 -opengl >=2.0.14") or dependency("--optional", "...")
    -- The declared dependencies are collected in ctx.deps; optional
    -- dependencies are recorded with a "?" prefix.
    function R.dependency(...)
        if not dependencies_mode then return end
        local args = {...}
        local opt_flag = ""
        if args[1] == "--optional" then
            opt_flag = "?"
            table.remove(args, 1)
        end
        local spec = pkg.normalize_spec(table.concat(args, " "))
        local deps = ctx.deps.dependencies
        deps[#deps + 1] = opt_flag .. spec
    end

    function R.provides(...)
        if not dependencies_mode then return end
        local spec = pkg.normalize_spec(table.concat({...}, " "))
        local provides = ctx.deps.provides
        provides[#provides + 1] = spec
    end

    function R.fail_config(msg)
        log_error(msg)
        util.fail(7, msg)
    end

    -- enter_archive(url, {curl_options = {...}, extract_options = {...}})
    function R.enter_archive(url, opts)
        if dependencies_mode then
            enter_dummy_build_dir()
            return
        end
        opts = opts or {}
        local archives_dir = os.getenv("LHELPER_WORKING_DIR") .. "/archives"
        local filename = recipe.archive_filename_of_url(url)
        local dest = archives_dir .. "/" .. filename
        if not util.is_file(dest) then
            local cmd = {"curl"}
            util.append_all(cmd, opts.curl_options or {})
            -- The option --insecure is used to ignore SSL certificate issues.
            -- The option --fail let the command fail if the response is a 404.
            util.append_all(cmd, {"--fail", "--retry", "5", "--retry-delay", "2",
                "--insecure", "-L", url, "-o", dest})
            log_print("downloading " .. url)
            -- Guard the download so that a Ctrl-C removes the partial file
            -- instead of leaving it behind as a corrupt cached archive.
            local code = download_guarded(dest, function()
                return log_run(cmd, { no_fail = true })
            end)
            if code ~= 0 then
                os.remove(dest)
                util.fail(5, "error downloading " .. url)
            end
        end
        clean_build_root()
        expand_enter_archive(dest, opts.extract_options)
    end

    function R.enter_git_repository(repo_url, repo_tag)
        if dependencies_mode then
            enter_dummy_build_dir()
            return
        end
        local archives_dir = os.getenv("LHELPER_WORKING_DIR") .. "/archives"
        local repo_name_short = util.basename(repo_url):gsub("%.git$", "")
        local checkout_name = repo_name_short .. "-" .. repo_tag
        local archive_filename = checkout_name .. ".tar.gz"
        -- FIXME: possible collisions in the filename, take the url into account
        if not util.is_file(archives_dir .. "/" .. archive_filename) then
            local temp_dir = archives_dir .. "/.tmp"
            util.rm_rf(temp_dir)
            util.mkdir_p(temp_dir)
            log_print("git clone --depth 1 --branch " .. repo_tag .. " " ..
                repo_url .. " " .. checkout_name)
            -- Guard the clone and archive creation so that a Ctrl-C removes the
            -- partial checkout directory instead of leaving it behind.
            download_guarded(temp_dir, function()
                -- Retry if there is a network error. It can happen with bad networks.
                local cloned = false
                for _ = 1, 3 do
                    local code = log_run({"git", "clone", "--depth", "1", "--branch",
                        repo_tag, repo_url, checkout_name},
                        { cwd = temp_dir, no_fail = true })
                    if code == 0 then
                        cloned = true
                        break
                    end
                    util.spawn({"sleep", "2"})
                end
                if not cloned then
                    util.rm_rf(temp_dir)
                    util.fail(5, "error cloning repository " .. repo_url)
                end
                util.rm_rf(temp_dir .. "/" .. checkout_name .. "/.git")
                log_run({"tar", "czf", archive_filename, checkout_name},
                    { cwd = temp_dir, on_error_code = 5,
                      error_message = "Got invalid archive: " .. archive_filename })
            end)
            os.rename(temp_dir .. "/" .. archive_filename,
                archives_dir .. "/" .. archive_filename)
            util.rm_rf(temp_dir)
            log_print("create archive " .. archive_filename .. " in " .. archives_dir)
        end
        clean_build_root()
        expand_enter_archive(archives_dir .. "/" .. archive_filename)
    end

    function R.inside_git_apply_patch(name)
        if dependencies_mode then return end
        log_run({"git", "apply", os.getenv("LHELPER_DIR") .. "/patch/" .. name .. ".patch"})
    end

    function R.inside_archive_apply_patch(name)
        if dependencies_mode then return end
        local patch_filename = os.getenv("LHELPER_DIR") .. "/patch/" .. name .. ".patch"
        -- "patch -p1 < file": use the -i option to avoid a shell redirection
        log_run({"patch", "-p1", "-i", patch_filename})
    end

    function R.install_pkgconfig_file(filename)
        if dependencies_mode then return end
        local dest = os.getenv("INSTALL_PREFIX") .. "/" ..
            os.getenv("LHELPER_PKGCONFIG_RPATH")
        log_print(string.format("Installing \"%s\" in \"%s\"", filename, dest))
        util.mkdir_p(dest)
        log_run({"cp", filename, dest})
    end

    -- Replace plain text in a file (used by recipes in place of sed).
    function R.file_replace(filename, old_text, new_text)
        if dependencies_mode then return end
        local content = util.read_file(filename)
        if not content then
            util.fail(6, "error: cannot read file " .. filename)
        end
        local escaped_old = util.pattern_escape(old_text)
        local escaped_new = new_text:gsub("%%", "%%%%")
        util.write_file(filename, (content:gsub(escaped_old, escaped_new)))
    end

    -- Run a generic command from a recipe, output to the recipe logs.
    function R.run(argv)
        if dependencies_mode then return end
        log_run(argv)
    end

    -- pkg-config helper for recipes (e.g. to append include flags to CFLAGS)
    function R.pkg_config(...)
        local cmd = {"pkg-config", ...}
        local output, code = util.capture(cmd)
        if code ~= 0 then return nil end
        return util.trim(output)
    end

    ---------------------------------------------------------------------------
    -- build_and_install

    -- Libraries based on the configure script sometimes check for a library
    -- using the system paths without using pkg-config. To avoid the problem
    -- add the environment's include and library directories to CC, CXX and
    -- LDFLAGS.
    local function add_lhelper_env_directory()
        local env_prefix = os.getenv("LHELPER_ENV_PREFIX")
        if util.is_windows then
            env_prefix = env_prefix:gsub("^/c/", "C:/")
        end
        util.setenv("CC", os.getenv("CC") .. " -I" .. env_prefix .. "/include")
        util.setenv("CXX", os.getenv("CXX") .. " -I" .. env_prefix .. "/include")
        local ldflags = os.getenv("LDFLAGS") or ""
        for _, libdir in ipairs(require("env").default_libdir()) do
            ldflags = ldflags .. (ldflags ~= "" and " " or "") ..
                "-L" .. env_prefix .. "/" .. libdir
        end
        util.setenv("LDFLAGS", ldflags)
        log_print("Setting the variables:")
        log_print("  CC=" .. os.getenv("CC"))
        log_print("  CXX=" .. os.getenv("CXX"))
        log_print("  LDFLAGS=" .. ldflags)
    end

    -- Do not use with cmake and meson based builds.
    local function add_build_type_compiler_flags(build_type)
        build_type = build_type:lower()
        local flag
        if build_type == "release" then flag = " -O3"
        elseif build_type == "debug" then flag = " -g" end
        if flag then
            util.setenv("CFLAGS", (os.getenv("CFLAGS") or "") .. flag)
            util.setenv("CXXFLAGS", (os.getenv("CXXFLAGS") or "") .. flag)
        end
    end

    local function run_with_destdir(argv, destdir, opts)
        util.setenv("DESTDIR", destdir)
        local ok, err = pcall(log_run, argv, opts)
        util.setenv("DESTDIR", nil)
        if not ok then error(err, 0) end
    end

    function R.build_and_install(kind, ...)
        if dependencies_mode then return end
        local args = {...}
        local destdir = os.getenv("INSTALL_PREFIX")
        if kind == "cmake" then
            if not R.test_commands("cmake", "ninja") then util.fail(3) end
            local options, setup_prefix = cmake_options(args)
            util.mkdir_p(".build")
            local cmd = {"cmake", "-G", "Ninja"}
            util.append_all(cmd, options)
            cmd[#cmd + 1] = ".."
            log_print("Using cmake command: ", table.concat(cmd, " "))
            log_run(cmd, { cwd = ".build",
                error_message = "error: while running cmake config" })
            log_run({"cmake", "--build", "."}, { cwd = ".build",
                error_message = "error: while running cmake build" })
            run_with_destdir({"cmake", "--build", ".", "--target", "install"},
                destdir, { cwd = ".build" })
            normalize_destdir_install(destdir, setup_prefix, true)
        elseif kind == "meson" then
            if not R.test_commands("meson", "ninja") then util.fail(3) end
            local options, setup_prefix = meson_options(args)
            local cmd = {"meson", "setup"}
            util.append_all(cmd, options)
            cmd[#cmd + 1] = ".."
            util.mkdir_p(".build")
            log_print("Using meson command: ", table.concat(cmd, " "))
            log_run(cmd, { cwd = ".build",
                error_message = "error: while running meson config" })
            log_run({"meson", "compile"}, { cwd = ".build",
                error_message = "error: while running meson build" })
            log_print("Using meson install command:  meson install --destdir=" .. destdir)
            log_run({"meson", "install", "--destdir=" .. destdir}, { cwd = ".build" })
            normalize_destdir_install(destdir, setup_prefix, true)
        elseif kind == "configure" then
            local required = {"make", "grep", "cmp", "diff"}
            if util.is_windows then required[#required + 1] = "bash" end
            if not R.test_commands(table.unpack(required)) then util.fail(3) end
            local options, build_type, setup_prefix =
                configure_options(args, os.getenv("BUILD_TYPE"))
            add_build_type_compiler_flags(build_type)
            add_lhelper_env_directory()
            local cmd
            if util.is_windows then
                cmd = {"bash", "./configure"}
            else
                cmd = {"./configure"}
            end
            util.append_all(cmd, options)
            log_print("Using configure command: ", table.concat(cmd, " "))
            log_run(cmd, { error_message = "error: while running configure script" })
            local make_cmd = {"make"}
            local cores = nproc()
            if cores then make_cmd[#make_cmd + 1] = "-j" .. cores end
            log_run(make_cmd, { error_message = "error: while running make build" })
            log_print("Using install command:  DESTDIR=" .. destdir .. " make install")
            run_with_destdir({"make", "DESTDIR=" .. destdir, "install"}, destdir, {})
            normalize_destdir_install(destdir, setup_prefix, false)
        else
            util.fail(1, string.format("error: unknown build type \"%s\"", kind))
        end
    end

    setmetatable(R, { __index = _G })
    return R
end

-- Run a recipe file. ctx as in make_recipe_env.
-- Returns the recipe's declarations {dependencies = {...}, provides = {...}}
-- (filled by the "dependencies" phase) or nil, error code, error message.
function recipe.run_recipe(recipe_filename, ctx)
    local content, read_err = util.read_file(recipe_filename)
    if not content then
        return nil, 1, read_err
    end
    ctx.deps = { dependencies = {}, provides = {} }
    local renv = recipe.make_recipe_env(ctx)
    local chunk, load_err = load(content, "@" .. recipe_filename, "t", renv)
    if not chunk then
        ctx.close_logs()
        return nil, 1, "error loading recipe: " .. load_err
    end
    local prev_dir = lhsys.getcwd()
    local ok, err = pcall(chunk)
    lhsys.chdir(prev_dir)
    ctx.close_logs()
    if not ok then
        if type(err) == "table" and err.code then
            return nil, err.code, err.msg
        end
        return nil, 1, tostring(err)
    end
    return ctx.deps
end

return recipe
