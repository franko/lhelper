#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if _WIN32
static char *path_to_unix(char *path_win) {
    int len = strlen(path_win);
    char *path = malloc(len + 1 + 16);
    if (!path) return NULL;
    char fchar = path_win[0], schar = path_win[1];
    if (((fchar >= 'a' && fchar <= 'z') || (fchar >= 'A' && fchar <= 'Z')) && schar == ':') {
        sprintf(path, "/%c%s", tolower(fchar), path_win + 2);
    } else {
        memcpy(path, path_win, len + 1);
    }
    int len_new = strlen(path);
    for (int i = 0; i < len_new; i++) {
        if (path[i] == '\\') {
            path[i] = '/';
        }
    }
    return path;
}
#endif

char *realpath_impl(char *rel_path) {
#if _WIN32
    char *abs_path_win = _fullpath(NULL, rel_path, 0);
    return path_to_unix(abs_path_win);
#else
    char *abs_path = realpath(rel_path, NULL);
#endif
    return abs_path;
}

static int is_dir_sep(int c) {
#if _WIN32
    return c == '/' || c == '\\';
#else
    return c == '/';
#endif
}

static int dirname_split(char *path, char **dir_path, char **basename) {
    int len = strlen(path);
    char *sep = path + len - 1;
    while (sep > path && !is_dir_sep(*sep)) {
        sep--;
    }
    if (!is_dir_sep(*sep)) return 1;
    char *bs = sep + 1;
    while (sep > path && is_dir_sep(*(sep - 1))) {
        sep--;
    }
    int dir_len = sep - path;
    int base_len = strlen(bs);
    *dir_path = malloc(dir_len + 1);
    *basename = malloc(base_len + 1);
    if (!*dir_path || !*basename) return 1;
    memcpy(*dir_path, path, dir_len);
    (*dir_path)[dir_len] = 0;
    memcpy(*basename, bs, base_len + 1);
    return 0;
}

static void remove_ending_slash(char *path) {
    char *p = path + strlen(path) - 1;
    while (p > path && is_dir_sep(*p)) {
        p--;
    }
    *(p + 1) = 0;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }
    char *rel_path = argv[1];
    remove_ending_slash(rel_path);
    char *dir_abs_path = realpath_impl(rel_path);
    if (dir_abs_path) {
        fprintf(stdout, "%s\n", dir_abs_path);
        return 0;
    }
    char *dir_path, *basename;
    if (dirname_split(rel_path, &dir_path, &basename) == 0) {
        if (basename[0] == '.') {
            goto no_such_file;
        }
        if (dir_path[0] != 0) {
            dir_abs_path = realpath_impl(dir_path);
        } else {
            dir_abs_path = dir_path;
        }
    } else {
        dir_abs_path = realpath_impl(".");
        basename = rel_path;
    }
    if (dir_abs_path) {
        fprintf(stdout, "%s/%s\n", dir_abs_path, basename);
        return 0;
    }
no_such_file:
    fprintf(stderr, "%s: %s: No such file or directory\n", argv[0], rel_path);
    return 1;
}
