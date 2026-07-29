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

-- The number of a version component: its leading digits, so that the
-- recipe revision of a version like "2.28.5+2" is ignored.
local function version_number(component)
    return tonumber((component or ""):match("^%d+")) or 0
end

-- Compare two dot-separated version strings.
-- Returns 0 (equal), 1 (a > b) or 2 (a < b), like the bash vercomp.
function pkg.vercomp(a, b)
    if a == b then return 0 end
    local va, vb = util.split(a, "."), util.split(b, ".")
    local n = math.max(#va, #vb)
    for i = 1, n do
        local na = version_number(va[i])
        local nb = version_number(vb[i])
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
-- matches a package spec, for example "sdl2 -opengl >=2.14.0". The entry
-- may be a registry line, "<name> [options] <version> <digest>": the
-- version is the first word after the name and the options.
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
        elseif not entry_version then
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

-- Add or update a package line "<package-name> [options] [version]" in a
-- list of registry lines, one line for each package.
function pkg.lines_add(lines, package_line)
    local package_name = package_line:match("^%S+")
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
    return lines
end

-- Find the registry line of a package in a list of registry lines.
function pkg.lines_query(lines, package_name)
    for _, line in ipairs(lines) do
        if line:match("^%S+") == package_name then
            return line
        end
    end
    return nil
end

-- Resolve a registry line: for a virtual package entry return the spec
-- part or, when the "link" flag is given, the provider's line.
function pkg.resolve_entry(line, link)
    if not line or util.trim(line) == "" then return nil end
    local pprov, pimpl = line:match("^(.-) : (.*)$")
    if pprov then
        return link and pimpl or pprov
    end
    return line
end

-- Query a package in a list of registry lines (see resolve_entry).
function pkg.query_lines(lines, package_name, link)
    return pkg.resolve_entry(pkg.lines_query(lines, package_name), link)
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

local function packages_filename(env_prefix)
    return env_prefix .. "/bin/lhelper-packages"
end

function pkg.registry_lines(env_prefix)
    return util.read_lines(packages_filename(env_prefix))
end

-- Register an installed package line together with the virtual packages
-- it provides (a list of package specs). The provide lines left by a
-- previous install of the same package are dropped so a reinstall does
-- not accumulate duplicate or stale "<virtual> : <package-line>" entries.
function pkg.register_package(env_prefix, package_line, provides)
    local filename = packages_filename(env_prefix)
    local package_name = package_line:match("^%S+")
    local lines = {}
    for _, line in ipairs(util.read_lines(filename)) do
        local pimpl = line:match("^.- : (.*)$")
        if not (pimpl and pimpl:match("^%S+") == package_name) then
            lines[#lines + 1] = line
        end
    end
    pkg.lines_add(lines, package_line)
    for _, provide_spec in ipairs(provides or {}) do
        lines[#lines + 1] = provide_spec .. " : " .. package_line
    end
    util.write_lines(filename, lines)
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
    return pkg.query_lines(pkg.registry_lines(env_prefix), package_name, link)
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
