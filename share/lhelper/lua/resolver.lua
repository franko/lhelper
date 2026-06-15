-- Load module path setup
pcall(function()
    local script_dir = debug.getinfo(1, "S").source:match("@?(.*/)")
    if script_dir then
        package.path = script_dir .. "?.lua;" .. package.path
    end
end)

local resolve_mod = require("resolve")

local LHELPER_DIR = os.getenv("LHELPER_DIR") or ""
local LHELPER_ENV_PREFIX = os.getenv("LHELPER_ENV_PREFIX") or ""
local LHELPER_RECIPES_DIR = os.getenv("LHELPER_RECIPES_DIR") or ""
local LH_RECIPES_DIR = os.getenv("LH_RECIPES_DIR") or LHELPER_RECIPES_DIR

local function find_lhelper_bin()
    return os.getenv("LHELPER_BIN") or (os.getenv("LHELPER_PREFIX") or (LHELPER_DIR .. "/../..")) .. "/bin/lhelper"
end

local LHELPER_BIN = find_lhelper_bin()

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- A native Windows Lua build routes os.execute/io.popen through cmd.exe, which
-- cannot parse the POSIX shell syntax used below (env-var prefixes, single
-- quotes, 2>/dev/null). Wrap such commands so they run under a POSIX shell.
local function shell(cmd)
    if IS_WINDOWS then
        return 'sh -c "' .. cmd:gsub('"', '\\"') .. '"'
    end
    return cmd
end

local function load_provides_table()
    local provides = {}
    local packages_file = LHELPER_ENV_PREFIX .. "/bin/lhelper-packages"
    local f = io.open(packages_file)
    if not f then return provides end
    for line in f:lines() do
        local virtual, real = line:match("^(.+)%s+:%s+(.+)$")
        if virtual then
            local vpkg = virtual:match("^(%S+)")
            local rpkg = real:match("^(%S+)")
            if vpkg and rpkg then
                if not provides[vpkg] then
                    provides[vpkg] = {}
                end
                table.insert(provides[vpkg], rpkg)
            end
        end
    end
    f:close()
    return provides
end

local PROVIDES = load_provides_table()

local function resolve_provides(pkg)
    local providers = PROVIDES[pkg]
    if not providers or #providers == 0 then
        return nil
    end
    if #providers == 1 then
        return providers[1]
    end
    io.stderr:write(string.format(
        "error: multiple packages provide \"%s\": %s\n",
        pkg, table.concat(providers, ", ")
    ))
    os.exit(2)
end

local function extract_deps(pkg, opts_str)
    local cmd = string.format(
        "LHELPER_ENV_PREFIX='%s' LH_RECIPES_DIR='%s' '%s' _extract_deps %s %s 2>/dev/null",
        LHELPER_ENV_PREFIX, LH_RECIPES_DIR, LHELPER_BIN, pkg, opts_str or ""
    )
    local f = io.popen(shell(cmd))
    if not f then return {} end
    local output = f:read("*a") or ""
    local ok, reason, rc = f:close()
    if not ok then
        io.stderr:write(string.format("error: failed to extract deps for %s (exit %s)\n", pkg, tostring(rc)))
        os.exit(1)
    end
    local deps = {}
    for raw_line in output:gmatch("[^\r\n]+") do
        local line = raw_line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^%?") then
            table.insert(deps, line)
        end
    end
    return deps
end

local function check_recipe_exists(pkg, ver_constraint)
    local cmd
    if ver_constraint then
        local op, ver = ver_constraint:match("^(>=|<=|>|<|=)([%d%.]+.*)$")
        if op and ver then
            cmd = string.format(
                "LH_RECIPES_DIR='%s' '%s' _check_recipe %s %s %s 2>/dev/null",
                LH_RECIPES_DIR, LHELPER_BIN, pkg, op, ver
            )
        else
            cmd = string.format(
                "LH_RECIPES_DIR='%s' '%s' _check_recipe %s 2>/dev/null",
                LH_RECIPES_DIR, LHELPER_BIN, pkg
            )
        end
    else
        cmd = string.format(
            "LH_RECIPES_DIR='%s' '%s' _check_recipe %s 2>/dev/null",
            LH_RECIPES_DIR, LHELPER_BIN, pkg
        )
    end
    local ok = os.execute(shell(cmd))
    return ok == 0 or ok == true
end

local function parse_dep_line(line)
    local parts = {}
    for part in line:gmatch("%S+") do
        table.insert(parts, part)
    end
    if #parts == 0 then return nil end
    local pkg = parts[1]
    local opts = {}
    local ver_constraint = nil
    for i = 2, #parts do
        if parts[i]:match("^-") then
            table.insert(opts, parts[i])
        elseif parts[i]:match("^[<>=]") then
            local op, ver = parts[i]:match("^(>=|<=|>|<|=)([%d%.]+)")
            if op and ver then
                ver_constraint = parts[i]
            end
        end
    end
    return pkg, table.concat(opts, " "), ver_constraint
end

local function discover_graph(target_pkg, target_opts_str)
    local queue = {}
    table.insert(queue, {pkg = target_pkg, optstr = target_opts_str})
    local visited = {}
    local edges = {}
    local qi = 1

    while qi <= #queue do
        local entry = queue[qi]
        qi = qi + 1

        local key = entry.pkg
        if entry.optstr ~= "" then
            key = key .. " " .. entry.optstr
        end
        if visited[key] then goto continue end
        visited[key] = true

        if not check_recipe_exists(entry.pkg, entry.ver_constraint) then
            local provider = resolve_provides(entry.pkg)
            if provider then
                table.insert(edges, entry.pkg .. " > " .. provider)
                if not visited[provider] then
                    table.insert(queue, {pkg = provider, optstr = ""})
                end
                goto continue
            end
            local err_msg = string.format("error: unknown recipe for package \"%s\"", entry.pkg)
            if entry.ver_constraint then
                err_msg = err_msg .. string.format(" (requires %s)", entry.ver_constraint)
            end
            io.stderr:write(err_msg .. "\n")
            os.exit(2)
        end

        local deps = extract_deps(entry.pkg, entry.optstr)
        local src_spec = entry.pkg
        if entry.optstr ~= "" then
            src_spec = src_spec .. " " .. entry.optstr
        end

        for _, dep_line in ipairs(deps) do
            local dep_pkg, dep_opts_str, ver_constraint = parse_dep_line(dep_line)
            if dep_pkg then
                local dep_key = dep_pkg
                if dep_opts_str ~= "" then
                    dep_key = dep_key .. " " .. dep_opts_str
                end

                table.insert(edges, src_spec .. " > " .. dep_key)

                if not visited[dep_key] then
                    local already_queued = false
                    for _, qe in ipairs(queue) do
                        local qk = qe.pkg
                        if qe.optstr ~= "" then
                            qk = qk .. " " .. qe.optstr
                        end
                        if qk == dep_key then
                            already_queued = true
                            break
                        end
                    end
                    if not already_queued then
                        table.insert(queue, {pkg = dep_pkg, optstr = dep_opts_str, ver_constraint = ver_constraint})
                    end
                end
            end
        end
        ::continue::
    end

    return edges
end

local function build_dag_text(edges)
    return table.concat(edges, "\n")
end

local function do_resolve(target_pkg, target_opts)
    local target_opts_str = target_opts and #target_opts > 0 and table.concat(target_opts, " ") or ""

    local edges = discover_graph(target_pkg, target_opts_str)

    if #edges == 0 then
        local spec = target_pkg
        if target_opts_str ~= "" then
            spec = spec .. " " .. target_opts_str
        end
        return {spec}
    end

    local dag_text = build_dag_text(edges)
    local order, cycle_nodes = resolve_mod.resolve(dag_text)

    if not order then
        io.stderr:write("error: dependency cycle detected:\n")
        local cycle_str = table.concat(cycle_nodes, " -> ")
        io.stderr:write("  " .. cycle_str .. "\n")
        os.exit(1)
    end

    return order
end

local function main(...)
    local args = {...}
    if #args < 1 then
        io.stderr:write("Usage: resolver.lua <package> [options]\n")
        os.exit(1)
    end

    local target_pkg = args[1]
    local target_opts = {}
    for i = 2, #args do
        table.insert(target_opts, args[i])
    end

    local order = do_resolve(target_pkg, target_opts)

    for _, pkg in ipairs(order) do
        print(pkg)
    end
end

main(...)
