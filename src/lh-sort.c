#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Should be a POD type. */
#define LH_ARRAY_TYPE char *
struct lh_array {
    LH_ARRAY_TYPE *data;
    int length;
    int size;
};
typedef struct lh_array lh_array;

lh_array *lh_array_new() {
    lh_array *ls = malloc(sizeof(lh_array));
    ls->size = 16;
    ls->data = malloc(sizeof(LH_ARRAY_TYPE) * ls->size);
    ls->length = 0;
    return ls;
}

void lh_array_append(lh_array *ls, LH_ARRAY_TYPE s) {
    if (ls->length >= ls->size) {
        int new_size = ls->size + 16;
        LH_ARRAY_TYPE *new_data = malloc(sizeof(LH_ARRAY_TYPE) * new_size);
        memcpy(new_data, ls->data, ls->size * sizeof(LH_ARRAY_TYPE));
        free(ls->data);
        ls->data = new_data;
        ls->size = new_size;
    }
    ls->data[ls->length++] = s;
}

lh_array *split_text(const char *text) {
    lh_array *words_list = lh_array_new();
    const char *text_end = text + strlen(text);
    while (text < text_end) {
        const char *limit = strchr(text, ' ');
        if (!limit) {
            limit = text_end;
        }
        const int word_len = limit - text;
        char *word = malloc(word_len + 1);
        memcpy(word, text, word_len);
        word[word_len] = 0;
        lh_array_append(words_list, word);

        text = limit;
        while (*text == ' ') {
            text++;
        }
    }
    return words_list;
}

/* Adapted from:
 * https://www.journaldev.com/37033/quicksort-algorithm-in-c-java-python
 */
#define LH_SORT_TYPE char *
#define LH_SORT_CMP(a,b) strcmp(a, b)
void lh_quicksort(LH_SORT_TYPE *words, int first, int last){
    int i, j, pivot;
    LH_SORT_TYPE temp;

    if (first < last){
        pivot = first;
        i = first;
        j = last;

        while (i < j) {
            while (LH_SORT_CMP(words[i], words[pivot]) <= 0 && i < last)
                i++;
            while (LH_SORT_CMP(words[j], words[pivot]) > 0)
                j--;
            if (i < j){
                temp = words[i];
                words[i] = words[j];
                words[j] = temp;
            }
        }
        temp = words[pivot];
        words[pivot] = words[j];
        words[j] = temp;
        lh_quicksort(words, first, j - 1);
        lh_quicksort(words, j + 1, last);
    }
}

int main(int argc, char *argv[]) {
    /* Takes a single argument as a string of space separated words. */
    if (argc != 2) {
        fprintf(stderr, "error: the command accept a single argument.\n");
        fprintf(stderr, "The list of words should be passed as a single argument with\n"
            "words separated by a space.\n\n");
        fprintf(stderr, "usage: %s <text>\n", argv[0]);
        return 1;
    }
    const char *text = argv[1];
    lh_array *words = split_text(text);
    lh_quicksort(words->data, 0, words->length - 1);
    for (int i = 0; i < words->length; i++) {
        fputs(words->data[i], stdout);
        fputs(" ", stdout);
    }
    fputs("\n", stdout);
    return 0;
}

