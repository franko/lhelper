-- General utilities: filesystem helpers, process spawning, string helpers.

local lhsys = require "lhsys"

local util = {}

util.platform = lhsys.platform
util.is_windows = (lhsys.platform == "windows")

-------------------------------------------------------------------------------
-- string helpers

function util.split(s, sep)
    sep = sep or "%s"
    local fields = {}
    for field in string.gmatch(s, "([^" .. sep .. "]+)") do
        fields[#fields + 1] = field
    end
    return fields
end

function util.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

function util.ends_with(s, suffix)
    return suffix == "" or s:sub(-#suffix) == suffix
end

function util.contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function util.append_all(list, other)
    for _, v in ipairs(other) do
        list[#list + 1] = v
    end
    return list
end

-- escape a string to be used literally inside a Lua pattern
function util.pattern_escape(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-------------------------------------------------------------------------------
-- path helpers

function util.basename(path)
    return path:match("([^/]*)/*$") or path
end

function util.dirname(path)
    local dir = path:match("^(.*)/[^/]*/*$")
    if not dir or dir == "" then
        if path:sub(1, 1) == "/" then return "/" end
        return "."
    end
    return dir
end

function util.realpath(path)
    local p, err = lhsys.realpath(path)
    if not p then error(err, 0) end
    return p
end

-------------------------------------------------------------------------------
-- filesystem helpers

function util.is_file(path)
    local st = lhsys.stat(path)
    return st ~= nil and st.type == "file"
end

function util.is_dir(path)
    local st = lhsys.stat(path)
    return st ~= nil and st.type == "dir"
end

function util.exists(path)
    return lhsys.stat(path) ~= nil
end

function util.mkdir_p(path)
    if util.is_dir(path) then return true end
    local parent = util.dirname(path)
    if parent ~= path and parent ~= "." and parent ~= "/" and not util.is_dir(parent) then
        local ok, err = util.mkdir_p(parent)
        if not ok then return nil, err end
    end
    return lhsys.mkdir(path)
end

function util.listdir(path)
    local list, err = lhsys.listdir(path)
    if not list then return {} end
    table.sort(list)
    return list
end

-- Recursively remove a file or a directory tree. Does not follow symlinks.
-- Returns true, or nil and a message for the first entry that could not be
-- removed. Removing the rest is still attempted, so that a single stubborn
-- file does not leave most of the tree behind.
function util.rm_rf(path)
    local st = lhsys.stat(path, "l")
    if not st then return true end
    if st.type == "dir" then
        local first_err
        for _, name in ipairs(util.listdir(path)) do
            local ok, err = util.rm_rf(path .. "/" .. name)
            if not ok and not first_err then first_err = err end
        end
        if first_err then return nil, first_err end
        return lhsys.rmdir(path)
    end
    return lhsys.remove(path)
end

-- List all the files (not directories) under root, as paths relative
-- to root itself.
function util.walk_files(root, prefix, result)
    prefix = prefix or ""
    result = result or {}
    for _, name in ipairs(util.listdir(root)) do
        local full, rel = root .. "/" .. name, prefix .. name
        local st = lhsys.stat(full, "l")
        if st and st.type == "dir" then
            util.walk_files(full, rel .. "/", result)
        else
            result[#result + 1] = rel
        end
    end
    return result
end

-- List files and directories under root (directories after their content),
-- relative to root.
function util.walk_all(root, prefix, result)
    prefix = prefix or ""
    result = result or {}
    for _, name in ipairs(util.listdir(root)) do
        local full, rel = root .. "/" .. name, prefix .. name
        result[#result + 1] = rel
        local st = lhsys.stat(full, "l")
        if st and st.type == "dir" then
            util.walk_all(full, rel .. "/", result)
        end
    end
    return result
end

-- Remove the empty directories below root, like "find . -empty -type d -delete".
function util.remove_empty_dirs(root)
    local entries = lhsys.listdir(root)
    if not entries then return false end
    local count = #entries
    for _, name in ipairs(entries) do
        local full = root .. "/" .. name
        local st = lhsys.stat(full, "l")
        if st and st.type == "dir" then
            if util.remove_empty_dirs(full) then
                count = count - 1
            end
        end
    end
    if count == 0 then
        return lhsys.rmdir(root) and true or false
    end
    return false
end

function util.read_file(filename)
    local f, err = io.open(filename, "rb")
    if not f then return nil, err end
    local content = f:read("a")
    f:close()
    return content
end

function util.write_file(filename, content)
    local f, err = io.open(filename, "wb")
    if not f then error(err, 0) end
    f:write(content)
    f:close()
end

function util.read_lines(filename)
    local lines = {}
    local f = io.open(filename, "r")
    if not f then return lines end
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

function util.write_lines(filename, lines)
    local f, err = io.open(filename, "w")
    if not f then error(err, 0) end
    for _, line in ipairs(lines) do
        f:write(line, "\n")
    end
    f:close()
end

-- Compare two files, like cmp -s. Returns true when identical.
function util.files_equal(file_a, file_b)
    local a = util.read_file(file_a)
    local b = util.read_file(file_b)
    return a ~= nil and a == b
end

-------------------------------------------------------------------------------
-- process helpers

-- Run a command given as an argv table. opts: {cwd=, stdout=, stderr=, append=}.
-- Returns the exit code.
function util.spawn(argv, opts)
    local code, err = lhsys.spawn(argv, opts)
    if not code then error(err, 0) end
    return code
end

function util.run_ok(argv, opts)
    return util.spawn(argv, opts) == 0
end

local capture_counter = 0

-- Run a command and capture its standard output.
-- Returns output, exit code.
function util.capture(argv, opts)
    opts = opts or {}
    capture_counter = capture_counter + 1
    local tmpname = (os.getenv("LHELPER_TMPDIR") or "/tmp") ..
        "/.lhelper-capture-" .. capture_counter
    local code = util.spawn(argv, {
        cwd = opts.cwd, stdout = tmpname,
        stderr = opts.stderr or (util.is_windows and "NUL" or "/dev/null"),
    })
    local output = util.read_file(tmpname) or ""
    os.remove(tmpname)
    return output, code
end

-- Find a command in PATH, like "command -v". The command may be given with
-- arguments: only the first word is checked.
function util.which(command)
    command = command:match("^%S+") or command
    if command:find("/") then
        return util.is_file(command) and command or nil
    end
    local path_sep = util.is_windows and ";" or ":"
    local path = os.getenv("PATH") or ""
    for dir in path:gmatch("([^" .. path_sep .. "]+)") do
        local candidate = dir .. "/" .. command
        if util.is_file(candidate) then return candidate end
        if util.is_windows and util.is_file(candidate .. ".exe") then
            return candidate .. ".exe"
        end
    end
    return nil
end

-- Save the current environment and return a function restoring it.
function util.env_snapshot()
    local lhsys_environ = lhsys.environ()
    return function()
        local current = lhsys.environ()
        for name in pairs(current) do
            if lhsys_environ[name] == nil then
                lhsys.setenv(name, nil)
            end
        end
        for name, value in pairs(lhsys_environ) do
            lhsys.setenv(name, value)
        end
    end
end

function util.getenv(name)
    return os.getenv(name)
end

function util.setenv(name, value)
    lhsys.setenv(name, value)
end

-------------------------------------------------------------------------------
-- error helper: raise an error carrying an exit code

function util.fail(code, msg)
    error({ code = code, msg = msg }, 0)
end

function util.printf(fmt, ...)
    io.write(string.format(fmt, ...))
end

return util
