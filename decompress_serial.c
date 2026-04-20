#include "common.h"

int decompress_serial(const char *input_file, const char *output_dir) {
    FILE *in = fopen(input_file, "rb");
    if (!in) {
        perror("fopen input");
        return -1;
    }
    
    char magic[MAGIC_SIZE];
    fread(magic, 1, MAGIC_SIZE, in);
    if (memcmp(magic, MAGIC, MAGIC_SIZE) != 0) {
        fprintf(stderr, "Invalid file format\n");
        fclose(in);
        return -1;
    }
    
    uint32_t file_count;
    fread(&file_count, 4, 1, in);
    
    uint32_t tree_size;
    fread(&tree_size, 4, 1, in);
    
    unsigned char *serialized_tree = malloc(tree_size);
    fread(serialized_tree, 1, tree_size, in);
    
    const unsigned char *tree_ptr = serialized_tree;
    unsigned long remaining = tree_size;
    HuffNode *tree = deserialize_tree(&tree_ptr, &remaining);
    
    if (!tree) {
        fprintf(stderr, "Failed to deserialize tree\n");
        free(serialized_tree);
        fclose(in);
        return -1;
    }
    
    mkdir(output_dir, 0755);
    
    printf("Decompressing %d files (serial)...\n", file_count);
    long long start_time = get_time_ms();
    
    for (uint32_t i = 0; i < file_count; i++) {
        uint16_t name_len;
        fread(&name_len, 2, 1, in);
        
        char *filename = malloc(name_len + 1);
        fread(filename, 1, name_len, in);
        filename[name_len] = '\0';
        
        uint32_t orig_size, comp_size;
        fread(&orig_size, 4, 1, in);
        fread(&comp_size, 4, 1, in);
        
        unsigned char *compressed = malloc(comp_size);
        fread(compressed, 1, comp_size, in);
        
        unsigned long decomp_size;
        unsigned char *decompressed = decompress_data(compressed, comp_size, tree, &decomp_size);
        free(compressed);
        
        if (decompressed) {
            char output_path[MAX_PATH];
            snprintf(output_path, sizeof(output_path), "%s/%s", output_dir, filename);
            
            FILE *out = fopen(output_path, "wb");
            if (out) {
                fwrite(decompressed, 1, decomp_size, out);
                fclose(out);
            }
            free(decompressed);
        }
        
        free(filename);
        
        if ((i + 1) % 10 == 0) {
            printf("  Decompressed %d/%d files\n", i + 1, file_count);
        }
    }
    
    fclose(in);
    free(serialized_tree);
    free_huff_tree(tree);
    
    long long end_time = get_time_ms();
    printf("Decompression complete! Time: %lld ms\n", end_time - start_time);
    
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input.huf> <output_dir>\n", argv[0]);
        return 1;
    }
    
    return decompress_serial(argv[1], argv[2]);
}
