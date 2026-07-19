-- Package registry and package spec handling.
--
-- Each environment has a "lhelper-packages" file with a line for each
-- installed package in the form "<name> [options] <recipe-version> <digest>".
-- Lines of the form "<virtual-spec> : <package-line>" record virtual
-- packages provided by an installed package.

local util = require "util"

local pkg = {}

-------------------------------------------------------------------------------
-- version comparison

-- Compare two dot-separated version strings.
-- Returns 0 (equal), 1 (a > b) or 2 (a < b), like the bash vercomp.
function pkg.vercomp(a, b)
    if a == b then return 0 end
    local va, vb = util.split(a, "."), util.split(b, ".")
    local n = math.max(#va, #vb)
    for i = 1, n do
        local na = tonumber(va[i]) or 0
        local nb = tonumber(vb[i]) or 0
        if na > nb then return 1 end
        if na < nb then return 2 end
    end
    return 0
end

-- Test "version <op> ref_version" where op is one of >=, <=, >, <, =.
function pkg.testvercomp(version, ref_version, op)
    local cmp = pkg.vercomp(version, ref_version)
    if cmp == 0 then return util.ends_with(op, "=") end
    if cmp == 1 then return util.starts_with(op, ">") end
    return util.starts_with(op, "<")
end

-------------------------------------------------------------------------------
-- package spec parsing and matching

-- Normalize a package spec line: sort the options and keep the other
-- arguments in place, e.g. "sdl2 -opengl -audio 2.0.1".
function pkg.normalize_spec(spec)
    local words = util.split(spec)
    local name = words[1]
    local options, rem = {}, {}
    for i = 2, #words do
        if util.starts_with(words[i], "-") then
            options[#options + 1] = words[i]
        else
            rem[#rem + 1] = words[i]
        end
    end
    table.sort(options)
    local coll = { name }
    util.append_all(coll, options)
    util.append_all(coll, rem)
    return table.concat(coll, " ")
end

-- Check that all the options in list a are included in list b.
local function options_subset(a, b)
    for _, opt in ipairs(a) do
        if not util.contains(b, opt) then return false end
    end
    return true
end

-- Test if a package entry, for example "sdl2 -threads -opengl 2.16.0",
-- matches a package spec, for example "sdl2 -opengl >=2.14.0".
-- Returns 0 on match or an error code like the bash implementation:
-- 1 name mismatch, 2 options mismatch, 3 version mismatch, 100 invalid spec.
function pkg.test_package_spec(spec_line, entry_line, skip_options)
    local spec_a = util.split(spec_line)
    local spec_name = spec_a[1]
    local spec_options = {}
    local spec_version, spec_comp
    for i = 2, #spec_a do
        local a = spec_a[i]
        if util.starts_with(a, "-") then
            spec_options[#spec_options + 1] = a
        elseif a:match("^[><]=") then
            spec_comp, spec_version = a:sub(1, 2), a:sub(3)
        elseif a:match("^[><=]") then
            spec_comp, spec_version = a:sub(1, 1), a:sub(2)
        else
            return 100
        end
    end

    local entry_a = util.split(entry_line)
    local entry_options = {}
    local entry_version
    for i = 2, #entry_a do
        local a = entry_a[i]
        if util.starts_with(a, "-") then
            entry_options[#entry_options + 1] = a
        else
            entry_version = a
        end
    end

    if spec_name ~= entry_a[1] then return 1 end
    if not skip_options and not options_subset(spec_options, entry_options) then
        return 2
    end
    if spec_version and entry_version and
        not pkg.testvercomp(entry_version, spec_version, spec_comp) then
        return 3
    end
    return 0
end

-------------------------------------------------------------------------------
-- packages register file

-- Add or update a package line "<package-name> [options] [version]" in
-- a register file, one line for each package.
function pkg.file_add(filename, package_line)
    local package_name = package_line:match("^%S+")
    local lines = util.read_lines(filename)
    local found = false
    for i, line in ipairs(lines) do
        if line:match("^%S+") == package_name then
            lines[i] = package_line
            found = true
        end
    end
    if not found then
        lines[#lines + 1] = package_line
    end
    util.write_lines(filename, lines)
end

function pkg.file_remove(filename, package_name)
    local lines = util.read_lines(filename)
    local new_lines = {}
    for _, line in ipairs(lines) do
        if line:match("^%S+") ~= package_name then
            new_lines[#new_lines + 1] = line
        end
    end
    util.write_lines(filename, new_lines)
end

function pkg.file_query(filename, package_name)
    for _, line in ipairs(util.read_lines(filename)) do
        if line:match("^%S+") == package_name then
            return line
        end
    end
    return nil
end

local function packages_filename(env_prefix)
    return env_prefix .. "/bin/lhelper-packages"
end

-- Register an installed package line. If the package provides some virtual
-- packages (recorded in the logs directory) register them too.
function pkg.register_package(env_prefix, package, package_line)
    pkg.file_add(packages_filename(env_prefix), package_line)
    local provides_file = env_prefix .. "/logs/" .. package .. "-provides"
    if util.is_file(provides_file) then
        local f = io.open(packages_filename(env_prefix), "a")
        for _, provide_line in ipairs(util.read_lines(provides_file)) do
            f:write(provide_line .. " : " .. package_line .. "\n")
        end
        f:close()
    end
end

function pkg.unregister_package(env_prefix, package)
    local filename = packages_filename(env_prefix)
    pkg.file_remove(filename, package)
    -- remove the virtual packages provided by the removed package
    local provided = {}
    for _, line in ipairs(util.read_lines(filename)) do
        local pprov, pimpl = line:match("^(.-) : (.*)$")
        if pprov and pimpl:match("^%S+") == package then
            provided[#provided + 1] = pprov:match("^%S+")
        end
    end
    for _, name in ipairs(provided) do
        pkg.file_remove(filename, name)
    end
end

-- Query an installed package. Returns the package's own line or, for a
-- virtual package, the spec part (or the provider's line when the "link"
-- flag is given).
function pkg.query_package(env_prefix, package_name, link)
    local line = pkg.file_query(packages_filename(env_prefix), package_name)
    if not line or util.trim(line) == "" then return nil end
    local pprov, pimpl = line:match("^(.-) : (.*)$")
    if pprov then
        return link and pimpl or pprov
    end
    return line
end

-------------------------------------------------------------------------------
-- installed package files

function pkg.package_list_filename(env_prefix, package)
    return env_prefix .. "/packages/" ..
        os.getenv("LHELPER_PACKAGE_VERSION") .. "/" .. package .. ".list"
end

function pkg.is_installed(env_prefix, package)
    return util.is_file(pkg.package_list_filename(env_prefix, package))
end

-- Remove all the files installed by a package and its .list file.
function pkg.remove_package_files(env_prefix, package)
    local list_filename = pkg.package_list_filename(env_prefix, package)
    for _, line in ipairs(util.read_lines(list_filename)) do
        local filename = env_prefix .. "/" .. line:gsub("^%./", "")
        if util.is_file(filename) then
            os.remove(filename)
        end
    end
    for _, name in ipairs(util.listdir(env_prefix)) do
        util.remove_empty_dirs(env_prefix .. "/" .. name)
    end
    os.remove(list_filename)
end

-------------------------------------------------------------------------------
-- system libraries

-- FIXME: add methods to detect CMake libraries and other system libraries
-- that may not have a pkg-config or cmake configuration.
function pkg.system_library_version(name)
    if util.which("pkg-config") then
        local output, code = util.capture({"pkg-config", "--modversion", name})
        if code == 0 then return util.trim(output) end
    end
    if util.which(name .. "-config") then
        local output, code = util.capture({name .. "-config", "--version"})
        if code == 0 then return util.trim(output) end
    end
    return nil
end

return pkg
