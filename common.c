#include "common.h"

static int compare_freq(const void *a, const void *b) {
    HuffNode *na = *(HuffNode**)a;
    HuffNode *nb = *(HuffNode**)b;
    return (na->freq > nb->freq) - (na->freq < nb->freq);
}

HuffNode* build_huffman_tree(unsigned long *freq) {
    HuffNode **nodes = malloc(ALPHABET_SIZE * sizeof(HuffNode*));
    int node_count = 0;
    for (int i = 0; i < ALPHABET_SIZE; i++) {
        if (freq[i] > 0) {
            nodes[node_count] = malloc(sizeof(HuffNode));
            nodes[node_count]->byte = i;
            nodes[node_count]->freq = freq[i];
            nodes[node_count]->left = nodes[node_count]->right = NULL;
            node_count++;
        }
    }
    if (node_count == 0) {
        free(nodes);
        return NULL;
    }
    if (node_count == 1) {
        HuffNode *parent = malloc(sizeof(HuffNode));
        parent->byte = 0;
        parent->freq = nodes[0]->freq;
        parent->left = nodes[0];
        parent->right = NULL;
        free(nodes);
        return parent;
    }
    while (node_count > 1) {
        qsort(nodes, node_count, sizeof(HuffNode*), compare_freq);
        HuffNode *left = nodes[0];
        HuffNode *right = nodes[1];
        HuffNode *parent = malloc(sizeof(HuffNode));
        parent->byte = 0;
        parent->freq = left->freq + right->freq;
        parent->left = left;
        parent->right = right;
        nodes[0] = parent;
        for (int i = 2; i < node_count; i++) {
            nodes[i-1] = nodes[i];
        }
        node_count--;
    }
    HuffNode *root = nodes[0];
    free(nodes);
    return root;
}

void generate_codes(HuffNode *root, HuffCode *table, unsigned long long code, unsigned char len) {
    if (!root) return;
    if (!root->left && !root->right) {
        table[root->byte].code = code;
        table[root->byte].len = len;
        return;
    }
    if (root->left) generate_codes(root->left, table, code << 1, len + 1);
    if (root->right) generate_codes(root->right, table, (code << 1) | 1, len + 1);
}

void serialize_tree(HuffNode *root, unsigned char **buffer, unsigned long *size) {
    if (!root) {
        *buffer = NULL;
        *size = 0;
        return;
    }
    unsigned char *left_buf = NULL, *right_buf = NULL;
    unsigned long left_size = 0, right_size = 0;
    serialize_tree(root->left, &left_buf, &left_size);
    serialize_tree(root->right, &right_buf, &right_size);
    if (!root->left && !root->right) {
        *size = 2 + left_size + right_size;
        *buffer = malloc(*size);
        (*buffer)[0] = 0;
        (*buffer)[1] = root->byte;
        if (left_size) memcpy(*buffer + 2, left_buf, left_size);
        if (right_size) memcpy(*buffer + 2 + left_size, right_buf, right_size);
    } else {
        *size = 1 + left_size + right_size;
        *buffer = malloc(*size);
        (*buffer)[0] = 1;
        if (left_size) memcpy(*buffer + 1, left_buf, left_size);
        if (right_size) memcpy(*buffer + 1 + left_size, right_buf, right_size);
    }
    free(left_buf);
    free(right_buf);
}

HuffNode* deserialize_tree(const unsigned char **buffer, unsigned long *remaining) {
    if (*remaining == 0) return NULL;
    HuffNode *node = malloc(sizeof(HuffNode));
    unsigned char type = (*buffer)[0];
    (*buffer)++; (*remaining)--;
    if (type == 0) {
        if (*remaining == 0) { free(node); return NULL; }
        node->byte = (*buffer)[0];
        node->freq = 0;
        node->left = node->right = NULL;
        (*buffer)++; (*remaining)--;
    } else {
        node->byte = 0;
        node->freq = 0;
        node->left = deserialize_tree(buffer, remaining);
        node->right = deserialize_tree(buffer, remaining);
    }
    return node;
}

unsigned char* compress_data(const unsigned char *data, unsigned long data_size,
                              HuffCode *table, unsigned long *out_size) {
    unsigned long total_bits = 0;
    for (unsigned long i = 0; i < data_size; i++)
        total_bits += table[data[i]].len;
    *out_size = (total_bits + 7) / 8;
    unsigned char *output = calloc(*out_size + 1, 1);
    unsigned long long buffer = 0;
    int bits_in_buffer = 0;
    unsigned long output_pos = 0;
    for (unsigned long i = 0; i < data_size; i++) {
        unsigned long long code = table[data[i]].code;
        unsigned char len = table[data[i]].len;
        buffer = (buffer << len) | code;
        bits_in_buffer += len;
        while (bits_in_buffer >= 8) {
            bits_in_buffer -= 8;
            output[output_pos++] = (buffer >> bits_in_buffer) & 0xFF;
        }
    }
    if (bits_in_buffer) {
        output[output_pos++] = (buffer << (8 - bits_in_buffer)) & 0xFF;
    }
    *out_size = output_pos;
    return output;
}

// ========== FUNCIÓN CORREGIDA con expected_size ==========
unsigned char* decompress_data(const unsigned char *compressed, unsigned long comp_size,
                                HuffNode *root, unsigned long expected_size, unsigned long *out_size) {
    if (!root) return NULL;
    unsigned char *output = malloc(expected_size + 1);
    unsigned long output_pos = 0;
    unsigned long bit_pos = 0;
    HuffNode *current = root;
    for (unsigned long i = 0; i < comp_size && output_pos < expected_size && bit_pos < comp_size * 8; i++) {
        unsigned char byte = compressed[i];
        for (int bit = 7; bit >= 0 && output_pos < expected_size && bit_pos < comp_size * 8; bit--) {
            int is_one = (byte >> bit) & 1;
            current = is_one ? current->right : current->left;
            if (!current) { free(output); return NULL; }
            if (!current->left && !current->right) {
                output[output_pos++] = current->byte;
                current = root;
            }
            bit_pos++;
        }
    }
    *out_size = output_pos;
    if (output_pos != expected_size) {
        fprintf(stderr, "Warning: decompressed %lu bytes, expected %lu\n", output_pos, expected_size);
    }
    return output;
}

unsigned long* compute_global_frequencies(const char *dir_path, char ***file_list, int *file_count) {
    unsigned long *global_freq = calloc(ALPHABET_SIZE, sizeof(unsigned long));
    *file_list = NULL;
    *file_count = 0;
    DIR *dir = opendir(dir_path);
    if (!dir) { perror("opendir"); return global_freq; }
    struct dirent *entry;
    char full_path[MAX_PATH];
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type == DT_REG) {
            snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, entry->d_name);
            *file_list = realloc(*file_list, (*file_count + 1) * sizeof(char*));
            (*file_list)[*file_count] = strdup(entry->d_name);
            (*file_count)++;
            FILE *f = fopen(full_path, "rb");
            if (f) {
                int c;
                while ((c = fgetc(f)) != EOF) global_freq[(unsigned char)c]++;
                fclose(f);
            }
        }
    }
    closedir(dir);
    return global_freq;
}

int get_file_list(const char *dir_path, char ***file_list) {
    DIR *dir = opendir(dir_path);
    if (!dir) return -1;
    int count = 0;
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_type == DT_REG) {
            *file_list = realloc(*file_list, (count + 1) * sizeof(char*));
            (*file_list)[count] = strdup(entry->d_name);
            count++;
        }
    }
    closedir(dir);
    return count;
}

void free_huff_tree(HuffNode *root) {
    if (!root) return;
    free_huff_tree(root->left);
    free_huff_tree(root->right);
    free(root);
}

long long get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}
