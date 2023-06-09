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

int string_buffer_init_read_file(const char *filename, struct string_buffer *buf, long max_length) {
#ifdef _WIN32
    FILE *f = fopen(filename, "rb");
#else
    FILE *f = fopen(filename, "r");
#endif
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    long length = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (length > max_length) return -1;
    if (string_buffer_init(buf, length + 1)) goto read_error_exit;
    long nread = fread(buf->data, 1, length, f);
    if (nread != length) {
        fprintf(stderr, "error reading file: %s\n", filename);
        goto read_error_exit;
    }
    buf->data[length] = 0;
    buf->len = length;
    fclose(f);
    return 0;
read_error_exit:
    fclose(f);
    return -1;
}


int string_buffer_contains_zero(struct string_buffer *buf, long read_length) {
  for (long i = 0; i < read_length && i < buf->len; i++) {
    if (buf->data[i] == 0) {
      return 1;
    }
  }
  return 0;
}

static int write_file_content(const char *filename, struct string_buffer *buf) {
#ifdef _WIN32
    FILE *of = fopen(filename, "wb");
#else
    FILE *of = fopen(filename, "w");
#endif
    size_t nwrite = fwrite(buf->data, 1, buf->len, of);
    fclose(of);
    return (nwrite < buf->len ? -1 : 0);
}


#define MAX_FILE_SIZE (50 * 1024 * 1024)
#define MAX_BYTES_BINARY_CHECK 1024
#define ERR_READING_FILE (-1)
#define ERR_BINARY_FILE (-13)

int find_replace_prefix_path(const char *filename, char *prefix[], int prefix_number, const char *pattern, const char *replacement) {
    const int replacement_len = strlen(replacement);
    const int pattern_len = strlen(pattern);
    struct string_buffer buffer[1];
    int prefix_i;

    if (string_buffer_init_read_file(filename, buffer, MAX_FILE_SIZE)) return ERR_READING_FILE;
    if (string_buffer_contains_zero(buffer, MAX_BYTES_BINARY_CHECK)) return ERR_BINARY_FILE;
    size_t length = buffer->len;

    struct string_buffer new_content[1];
    if (string_buffer_init(new_content, length + 64)) return -1;

    char **patterns_list = malloc(prefix_number * sizeof(char *));
    for (prefix_i = 0; prefix_i < prefix_number; prefix_i++) {
        const int prefix_len = strlen(prefix[prefix_i]);
        patterns_list[prefix_i] = malloc(prefix_len + pattern_len + 1);
        memcpy(patterns_list[prefix_i], prefix[prefix_i], prefix_len);
        memcpy(patterns_list[prefix_i] + prefix_len, pattern, pattern_len + 1);
    }

    char *current = buffer->data;
    char *buffer_end = buffer->data + length;
    while (current < buffer_end) {
        char *current_next = buffer_end;
        int replacement_done = 0;
        for (prefix_i = 0; prefix_i < prefix_number; prefix_i++) {
            const int match_len = strlen(prefix[prefix_i]) + pattern_len;
            char *p = strstr(current, patterns_list[prefix_i]);
            if (p) {
                if (!char_is_alphanum_dash(*(p + match_len)) && (p == buffer->data || !char_is_alphanum_dash(*(p - 1)))) {
                    if (add_string(new_content, current, p - current)) goto error_exit;
                    if (add_string(new_content, replacement, replacement_len)) goto error_exit;
                    current_next = p + match_len;
                    replacement_done = 1;
                    break;
                } else {
                    if (p + 1 < current_next) {
                        current_next = p + 1;
                    }
                }
            }
        }
        if (!replacement_done) {
            add_string(new_content, current, current_next - current);
        }
        current = current_next;
    }

    if (write_file_content(filename, new_content)) {
        fprintf(stderr, "Fatal error writing modification in file: %s", filename);
        goto error_exit;
    }

    free(new_content->data);
    free(buffer->data);
    return 0;

error_exit:
    free(new_content->data);
    free(buffer->data);
    return -1;
}


int find_replace_path(const char *filename, const char *pattern, const char *replacement) {
    const int replacement_len = strlen(replacement);
    const int pattern_len = strlen(pattern);
    struct string_buffer buffer[1];
    if (string_buffer_init_read_file(filename, buffer, MAX_FILE_SIZE)) return ERR_READING_FILE;
    if (string_buffer_contains_zero(buffer, MAX_BYTES_BINARY_CHECK)) return ERR_BINARY_FILE;
    size_t length = buffer->len;

    struct string_buffer new_content[1];
    if (string_buffer_init(new_content, length + 64)) return -1;

    char *current = buffer->data;
    char *buffer_end = buffer->data + length;
    while (current < buffer_end) {
        char *p = strstr(current, pattern);
        if (p) {
            if (!char_is_alphanum_dash(*(p + pattern_len)) && (p  == buffer->data || !char_is_alphanum_dash(*(p - 1)))) {
                if (add_string(new_content, current, p - current)) goto error_exit;
                if (add_string(new_content, replacement, replacement_len)) goto error_exit;
                current = p + pattern_len;
            } else {
                add_string(new_content, current, p - current + 1);
                current = p + 1;
            }
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
    free(buffer->data);
    return 0;

error_exit:
    free(new_content->data);
    free(buffer->data);
    return -1;
}

void *
this_memmem(const void *haystack, size_t n, const void *needle, size_t m) {
    if (m > n || !m || !n)
        return NULL;
    if (m > 1) {
        const unsigned char*  y = (const unsigned char*) haystack;
        const unsigned char*  x = (const unsigned char*) needle;
        size_t                j = 0;
        size_t                k = 1, l = 2;
        if (x[0] == x[1]) {
            k = 2;
            l = 1;
        }
        while (j <= n-m) {
            if (x[1] != y[j+1]) {
                j += k;
            } else {
                if (!memcmp(x+2, y+j+2, m-2) && x[0] == y[j])
                    return (void*) &y[j];
                j += l;
            }
        }
    } else {
        /* degenerate case */
        return memchr(haystack, ((unsigned char*)needle)[0], n);
    }
    return NULL;
}

int find_prefix_file_any(const char *filename, const char *pattern) {
    const int pattern_len = strlen(pattern);
    struct string_buffer buffer[1];
    if (string_buffer_init_read_file(filename, buffer, MAX_FILE_SIZE)) return -1;
    size_t length = buffer->len;

    char *current = buffer->data;
    char *buffer_end = buffer->data + length;
    int prefix_found = 0;
    while (current < buffer_end) {
        char *p = this_memmem(current, buffer->len, pattern, pattern_len);
        if (p) {
            if (!char_is_alphanum_dash(*(p + pattern_len)) && (p  == buffer->data || !char_is_alphanum_dash(*(p - 1)))) {
                prefix_found = 1;
                break;
            } else {
                current = p + 1;
            }
        } else {
            current = buffer_end;
        }
    }

    free(buffer->data);
    return prefix_found;
}

int main(int argc, char *argv[]) {
    if (argc < 4) return 1;
    int status = 0;
    const char *pattern = argv[2];
    const char *replacement = argv[3];
    const char *pattern_base = pattern;
    const char *pattern_msys = NULL;
    if (char_is_alpha(*pattern) && pattern[1] == ':' && pattern[2] == '/') {
        pattern_base = pattern + 2;
        const int drive_letter = tolower(*pattern);
        char *msysroot = getenv("LH_MSYSROOT");
        /* We use the variable above to recognize the MSYS Windows root directory. */
        if (msysroot && strlen(msysroot) > 0 && strncmp(pattern, msysroot, strlen(msysroot)) == 0) {
            /* Replace by using a "/" in the pattern instead of LH_MSYSROOT */
            pattern_msys = pattern + strlen(msysroot);
            if (*(pattern_msys - 1) == '/') {
                pattern_msys -= 1;
            }
            status = find_replace_path(argv[1], pattern_msys, replacement);
        }
        if (status == 0) {
            char prefix_data[64];
            char *prefix_array[3] = {prefix_data, prefix_data + 8, prefix_data + 16};
            sprintf(prefix_array[0], "%c:", drive_letter);
            sprintf(prefix_array[1], "%c:", toupper(drive_letter));
            sprintf(prefix_array[2], "/%c", drive_letter);
            status = find_replace_prefix_path(argv[1], prefix_array, 3, pattern_base, replacement);
        }
    } else {
        status = find_replace_path(argv[1], pattern, replacement);
    }
    if (status == ERR_BINARY_FILE) {
        if (!find_prefix_file_any(argv[1], pattern_base) && (!pattern_msys || !find_prefix_file_any(argv[1], pattern_msys))) {
            status = 0;
        }
    }
    return status;
}

