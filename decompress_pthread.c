#include "common.h"
#include <pthread.h>

typedef struct {
    const char *input_file;
    unsigned long start_offset;
    int file_count;
    const char *output_dir;
    HuffNode *tree;
    int thread_id;
} ThreadDecompressArgs;

void* decompress_thread(void *arg) {
    ThreadDecompressArgs *args = (ThreadDecompressArgs*)arg;
    FILE *in = fopen(args->input_file, "rb");
    if (!in) return NULL;
    fseek(in, args->start_offset, SEEK_SET);
    char output_path[MAX_PATH];
    
    for (int i = 0; i < args->file_count; i++) {
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
        unsigned char *decompressed = decompress_data(compressed, comp_size, args->tree, orig_size, &decomp_size);
        free(compressed);
        
        if (decompressed) {
            snprintf(output_path, sizeof(output_path), "%s/%s", args->output_dir, filename);
            FILE *out = fopen(output_path, "wb");
            if (out) {
                fwrite(decompressed, 1, decomp_size, out);
                fclose(out);
            }
            free(decompressed);
        }
        free(filename);
    }
    fclose(in);
    return NULL;
}

int decompress_pthread(const char *input_file, const char *output_dir, int num_threads) {
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
    
    // Leer offsets
    typedef struct { unsigned long offset; } FileOffset;
    FileOffset *offsets = malloc(file_count * sizeof(FileOffset));
    unsigned long current_offset = ftell(in);
    
    for (uint32_t i = 0; i < file_count; i++) {
        offsets[i].offset = current_offset;
        uint16_t name_len;
        fread(&name_len, 2, 1, in);
        fseek(in, name_len, SEEK_CUR);
        uint32_t orig_size, comp_size;
        fread(&orig_size, 4, 1, in);
        fread(&comp_size, 4, 1, in);
        fseek(in, comp_size, SEEK_CUR);
        current_offset = ftell(in);
    }
    fclose(in);
    
    int files_per_thread = file_count / num_threads;
    int remainder = file_count % num_threads;
    pthread_t threads[num_threads];
    ThreadDecompressArgs args[num_threads];
    
    printf("Decompressing %d files with %d threads...\n", file_count, num_threads);
    long long start_time = get_time_ms();
    
    int start = 0;
    for (int i = 0; i < num_threads; i++) {
        int end = start + files_per_thread + (i < remainder ? 1 : 0);
        int count = end - start;
        args[i] = (ThreadDecompressArgs){
            .input_file = input_file,
            .start_offset = offsets[start].offset,
            .file_count = count,
            .output_dir = output_dir,
            .tree = tree,
            .thread_id = i
        };
        pthread_create(&threads[i], NULL, decompress_thread, &args[i]);
        start = end;
    }
    
    for (int i = 0; i < num_threads; i++) pthread_join(threads[i], NULL);
    
    free(offsets);
    free(serialized_tree);
    free_huff_tree(tree);
    
    long long end_time = get_time_ms();
    printf("Decompression complete! Time: %lld ms\n", end_time - start_time);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <input.huf> <output_dir> <num_threads>\n", argv[0]);
        return 1;
    }
    int num_threads = atoi(argv[3]);
    if (num_threads < 1) num_threads = 1;
    return decompress_pthread(argv[1], argv[2], num_threads);
}
