check_commands("meson", "ninja", "git")

enter_git_repository("https://github.com/franko/agg.git", "v" .. version)

-- FT_Outline.tags is "unsigned char *" in current freetype but the agg
-- freetype font engine declares the local pointer as "char *", which does not
-- compile. The tag values are only read, so widening the local type is enough.
inside_archive_apply_patch("agg-2.4-freetype-outline-tags")

build_and_install("meson", table.unpack(options))
