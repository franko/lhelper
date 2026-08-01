-- The configure script requires the commands cmp and diff.
check_commands("make", "cmp", "diff", getenv("CC"))

local enables = {
    "pcre2-8",
    "unicode",
    "newline-is-anycrlf",
}

local disables = {
    "pcre2-16",
    "pcre2-32",
    "debug",
    "jit",
    "ebcdic",
    "pcre2grep-jit",
    "pcre2grep-callout",
    "pcre2grep-callout-fork",
    "pcre2grep-libz",
    "pcre2grep-libbz2",
}

local opts = {}
for _, name in ipairs(enables) do
    opts[#opts + 1] = "--enable-" .. name
end
for _, name in ipairs(disables) do
    opts[#opts + 1] = "--disable-" .. name
end

-- The old sourceforge location can be used up to version 10.36 but in lhelper
-- we don't provide versions older than 10.39.
-- enter_archive("https://sourceforge.net/projects/pcre/files/pcre2/" ..
--     version .. "/pcre2-" .. version .. ".tar.gz")
enter_archive("https://github.com/PhilipHazel/pcre2/releases/download/pcre2-" ..
    version .. "/pcre2-" .. version .. ".tar.gz")
build_and_install("configure", table.unpack(opts))