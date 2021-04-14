/* Helper utility. It replace all occurrences of an absolute path with a
  replacement text within a file. If the absolute path begins with a drive
  letter like "C:" it replace all occurrences of the given path whether
  they begin by "c:/", "C:/" or /c/".
*/

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct string_buffer {
    char *data;
    size_t len;
    size_t size;
};


int string_buffer_init(struct string_buffer *buf, int size) {
    char *new_data = malloc(size);
    if (!new_data) return -1;
    buf->data = new_data;
    buf->data[0] = 0;
    buf->len = 0;
    buf->size = size;
    return 0;
}

int add_string(struct string_buffer *dest, const char *text, int text_len) {
    size_t new_size = dest->len + text_len + 1;
    if (new_size > dest->size) {
        char *new_data = malloc(new_size);
        if (!new_data) return -1;
        memcpy(new_data, dest->data, dest->len + 1);
        free(dest->data);
        dest->data = new_data;
        dest->size = new_size;
    }
    memcpy(dest->data + dest->len, text, text_len);
    dest->len += text_len;
    dest->data[dest->len] = 0;
    return 0;
}

int char_is_alpha(int code) {
    return (code >= 'a' && code <= 'z') ||
        (code >= 'A' && code <= 'Z');
}

int char_is_alphanum_dash(int code) {
    return (code >= 'a' && code <= 'z') ||
        (code >= 'A' && code <= 'Z') ||
        (code >= '0' && code <= '9') ||
        (code == '-' || code == '_');
}

static char *read_file_content(const char *filename, long *length) {
    FILE *f = fopen(filename, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    *length = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buffer = malloc(*length);
    if (buffer) {
      fread(buffer, 1, *length, f);
    }
    fclose(f);
    return buffer;
}


static int write_file_content(const char *filename, struct string_buffer *buf) {
    FILE *of = fopen(filename, "w");
    size_t nwrite = fwrite(buf->data, 1, buf->len, of);
    fclose(of);
    return (nwrite < buf->len ? -1 : 0);
}


int find_replace_prefix_path(const char *filename, char *prefix[], int prefix_len, const char *pattern, const char *replacement) {
    const int replacement_len = strlen(replacement);
    const int pattern_len = strlen(pattern);
    long length;
    char * const buffer = read_file_content(filename, &length);
    if (!buffer) return -1;

    struct string_buffer new_content[1];
    if (string_buffer_init(new_content, length + 64)) return -1;

    char *current = buffer;
    char *buffer_end = buffer + length;
    while (*current) {
        int prefix_i;
        for (prefix_i = 0; prefix_i < prefix_len; prefix_i++) {
            char *p = strstr(current, prefix[prefix_i]);
            if (p) {
                char *match_start = p;
                p += strlen(prefix[prefix_i]);
                if (strncmp(p, pattern, pattern_len) == 0) {
                    if (!char_is_alphanum_dash(*(p + pattern_len))) {
                        if (add_string(new_content, current, match_start - current)) goto error_exit;
                        if (add_string(new_content, replacement, replacement_len)) goto error_exit;
                        current = p + pattern_len;
                        break;
                    }
                }
            }
        }
        if (prefix_i >= prefix_len) { // no match
            add_string(new_content, current, buffer_end - current);
            current = buffer_end;
        }
    }
        
    if (write_file_content(filename, new_content)) {
        fprintf(stderr, "Fatal error writing modification in file: %s", filename);
        goto error_exit;
    }

    free(new_content->data);
    free(buffer);
    return 0;

error_exit:
    free(new_content->data);
    free(buffer);
    return -1;
}            


int find_replace_path(const char *filename, const char *pattern, const char *replacement) {
    const int replacement_len = strlen(replacement);
    const int pattern_len = strlen(pattern);
    long length;
    char *const buffer = read_file_content(filename, &length);
    if (!buffer) return -1;

    struct string_buffer new_content[1];
    if (string_buffer_init(new_content, length + 64)) return -1;

    char *current = buffer;
    char *buffer_end = buffer + length;
    while (*current) {
        char *p = strstr(current, pattern);
        if (p && !char_is_alphanum_dash(*(p + pattern_len))) {
            if (add_string(new_content, current, p - current)) goto error_exit;
            if (add_string(new_content, replacement, replacement_len)) goto error_exit;
            current = p + pattern_len;
        } else {
            add_string(new_content, current, buffer_end - current);
            current = buffer_end;
        }
    }
        
    if (write_file_content(filename, new_content)) {
        fprintf(stderr, "Fatal error writing modification in file: %s", filename);
        goto error_exit;
    }

    free(new_content->data);
    free(buffer);
    return 0;

error_exit:
    free(new_content->data);
    free(buffer);
    return -1;
}

int main(int argc, char *argv[]) {
    if (argc < 4) return 1;
    const char *pattern = argv[2];
    const char *replacement = argv[3];
    if (char_is_alpha(*pattern) && pattern[1] == ':') {
        const int drive_letter = tolower(*pattern);
        char prefix_data[64];
        char *prefix_array[3] = {prefix_data, prefix_data + 8, prefix_data + 16};
        sprintf(prefix_array[0], "%c:", drive_letter);
        sprintf(prefix_array[1], "%c:", toupper(drive_letter));
        sprintf(prefix_array[2], "/%c", drive_letter);
        return find_replace_prefix_path(argv[1], prefix_array, 3, pattern + 2, replacement);
    } else {
        return find_replace_path(argv[1], pattern, replacement);
    }
    return 0;
}

