#ifndef COMMON_H
#define COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#define MAGIC "HUF1"
#define MAGIC_SIZE 4
#define ALPHABET_SIZE 256
#define MAX_PATH 1024
#define BUFFER_SIZE 4096

// Nodo del árbol de Huffman
typedef struct HuffNode {
    unsigned char byte;
    unsigned long freq;
    struct HuffNode *left, *right;
} HuffNode;

// Tabla de códigos (global)
typedef struct {
    unsigned long long code;
    unsigned char len;
} HuffCode;

// Funciones principales
unsigned long* compute_global_frequencies(const char *dir_path, char ***file_list, int *file_count);
HuffNode* build_huffman_tree(unsigned long *freq);
void generate_codes(HuffNode *root, HuffCode *table, unsigned long long code, unsigned char len);
unsigned char* compress_data(const unsigned char *data, unsigned long data_size, HuffCode *table, unsigned long *out_size);
unsigned char* decompress_data(const unsigned char *compressed, unsigned long comp_size, HuffNode *root, unsigned long *out_size);
void serialize_tree(HuffNode *root, unsigned char **buffer, unsigned long *size);
HuffNode* deserialize_tree(const unsigned char **buffer, unsigned long *remaining);
void free_huff_tree(HuffNode *root);
long long get_time_ms();
int get_file_list(const char *dir_path, char ***file_list);

#endif
