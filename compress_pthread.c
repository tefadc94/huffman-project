#include "common.h"
#include <pthread.h>

typedef struct {
    char **files;
    int start;
    int end;
    int thread_id;
    char *dir_path;
    HuffCode *table;
    char **output_buffers;  // Cambiado a char**
    size_t *output_sizes;
} ThreadArgs;

void* compress_thread(void *arg) {
    ThreadArgs *args = (ThreadArgs*)arg;
    
    FILE *stream = open_memstream(&args->output_buffers[args->thread_id], 
                                   &args->output_sizes[args->thread_id]);
    if (!stream) {
        return NULL;
    }
    
    for (int i = args->start; i < args->end; i++) {
        char full_path[MAX_PATH];
        snprintf(full_path, sizeof(full_path), "%s/%s", args->dir_path, args->files[i]);
        
        FILE *f = fopen(full_path, "rb");
        if (!f) continue;
        
        fseek(f, 0, SEEK_END);
        unsigned long orig_size = ftell(f);
        fseek(f, 0, SEEK_SET);
        
        unsigned char *data = malloc(orig_size);
        fread(data, 1, orig_size, f);
        fclose(f);
        
        unsigned long comp_size;
        unsigned char *compressed = compress_data(data, orig_size, args->table, &comp_size);
        free(data);
        
        uint16_t name_len = strlen(args->files[i]);
        fwrite(&name_len, 2, 1, stream);
        fwrite(args->files[i], 1, name_len, stream);
        
        uint32_t orig_size_be = orig_size;
        uint32_t comp_size_be = comp_size;
        fwrite(&orig_size_be, 4, 1, stream);
        fwrite(&comp_size_be, 4, 1, stream);
        fwrite(compressed, 1, comp_size, stream);
        
        free(compressed);
    }
    
    fclose(stream);
    return NULL;
}

int compress_directory_pthread(const char *dir_path, const char *output_file, int num_threads) {
    char **file_list = NULL;
    int file_count;
    
    printf("Step 1: Computing global frequencies...\n");
    unsigned long *global_freq = compute_global_frequencies(dir_path, &file_list, &file_count);
    
    if (file_count == 0) {
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
    
    int files_per_thread = file_count / num_threads;
    int remainder = file_count % num_threads;
    
    pthread_t threads[num_threads];
    ThreadArgs args[num_threads];
    char *buffers[num_threads];  // Cambiado a char*
    size_t sizes[num_threads];
    
    printf("Step 5: Compressing with %d threads...\n", num_threads);
    long long start_time = get_time_ms();
    
    int start = 0;
    for (int i = 0; i < num_threads; i++) {
        int end = start + files_per_thread + (i < remainder ? 1 : 0);
        
        args[i] = (ThreadArgs){
            .files = file_list,
            .start = start,
            .end = end,
            .thread_id = i,
            .dir_path = (char*)dir_path,
            .table = table,
            .output_buffers = buffers,
            .output_sizes = sizes
        };
        
        pthread_create(&threads[i], NULL, compress_thread, &args[i]);
        start = end;
    }
    
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }
    
    FILE *out = fopen(output_file, "wb");
    if (!out) {
        perror("fopen output");
        return -1;
    }
    
    fwrite(MAGIC, 1, MAGIC_SIZE, out);
    uint32_t file_count_be = file_count;
    fwrite(&file_count_be, 4, 1, out);
    
    uint32_t tree_size_be = tree_size;
    fwrite(&tree_size_be, 4, 1, out);
    fwrite(serialized_tree, 1, tree_size, out);
    
    for (int i = 0; i < num_threads; i++) {
        fwrite(buffers[i], 1, sizes[i], out);
        free(buffers[i]);
    }
    
    fclose(out);
    free(serialized_tree);
    free_huff_tree(tree);
    for (int i = 0; i < file_count; i++) free(file_list[i]);
    free(file_list);
    
    long long end_time = get_time_ms();
    printf("Time: %lld ms\n", end_time - start_time);
    
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <input_directory> <output_file> <num_threads>\n", argv[0]);
        return 1;
    }
    
    int num_threads = atoi(argv[3]);
    if (num_threads < 1) num_threads = 1;
    
    return compress_directory_pthread(argv[1], argv[2], num_threads);
}
