local core = {}

function core.init()
    -- can be used for initialization.
end

function core.run()
    local p = process.start({"ls", "-l"}, {stdout = process.REDIRECT_PIPE})
    repeat
        local s = p:read_stdout()
        if s and s ~= "" then print("OUTPUT:", s) end
    until not s
    p:wait()
    print("PROCESS END")
end

return core
