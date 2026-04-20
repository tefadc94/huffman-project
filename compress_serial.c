#include "common.h"

int compress_directory(const char *dir_path, const char *output_file) {
    char **file_list = NULL;
    int file_count;
    
    printf("Step 1: Computing global frequencies...\n");
    unsigned long *global_freq = compute_global_frequencies(dir_path, &file_list, &file_count);
    
    if (file_count == 0) {
        fprintf(stderr, "No files found in directory\n");
        free(global_freq);
        return -1;
    }
    
    printf("Found %d files\n", file_count);
    
    printf("Step 2: Building Huffman tree...\n");
    HuffNode *tree = build_huffman_tree(global_freq);
    free(global_freq);
    
    printf("Step 3: Generating codes...\n");
    HuffCode table[ALPHABET_SIZE] = {0};
    generate_codes(tree, table, 0, 0);
    
    printf("Step 4: Serializing tree...\n");
    unsigned char *serialized_tree = NULL;
    unsigned long tree_size;
    serialize_tree(tree, &serialized_tree, &tree_size);
    
    printf("Step 5: Compressing files...\n");
    
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("fopen output");
        free_huff_tree(tree);
        free(serialized_tree);
        return -1;
    }
    
    fwrite(MAGIC, 1, MAGIC_SIZE, out);
    uint32_t file_count_be = file_count;
    fwrite(&file_count_be, 4, 1, out);
    
    uint32_t tree_size_be = tree_size;
    fwrite(&tree_size_be, 4, 1, out);
    fwrite(serialized_tree, 1, tree_size, out);
    
    for (int i = 0; i < file_count; i++) {
        char full_path[MAX_PATH];
        snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, file_list[i]);
        
        FILE *f = fopen(full_path, "rb");
        if (!f) {
            perror("fopen input");
            continue;
        }
        
        fseek(f, 0, SEEK_END);
        unsigned long orig_size = ftell(f);
        fseek(f, 0, SEEK_SET);
        
        unsigned char *data = malloc(orig_size);
        fread(data, 1, orig_size, f);
        fclose(f);
        
        unsigned long comp_size;
        unsigned char *compressed = compress_data(data, orig_size, table, &comp_size);
        free(data);
        
        uint16_t name_len = strlen(file_list[i]);
        fwrite(&name_len, 2, 1, out);
        fwrite(file_list[i], 1, name_len, out);
        
        uint32_t orig_size_be = orig_size;
        uint32_t comp_size_be = comp_size;
        fwrite(&orig_size_be, 4, 1, out);
        fwrite(&comp_size_be, 4, 1, out);
        fwrite(compressed, 1, comp_size, out);
        
        free(compressed);
        
        if ((i + 1) % 10 == 0) {
            printf("  Compressed %d/%d files\n", i + 1, file_count);
        }
    }
    
    fclose(out);
    free(serialized_tree);
    free_huff_tree(tree);
    for (int i = 0; i < file_count; i++) free(file_list[i]);
    free(file_list);
    
    printf("Compression complete! Output: %s\n", output_file);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input_directory> <output_file>\n", argv[0]);
        return 1;
    }
    
    long long start = get_time_ms();
    int result = compress_directory(argv[1], argv[2]);
    long long end = get_time_ms();
    
    printf("Time: %lld ms\n", end - start);
    return result;
}
