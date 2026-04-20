#include "common.h"
#include <sys/wait.h>

typedef struct {
    char **files;
    int start;
    int end;
    char *dir_path;
    HuffCode *table;
} ProcessTask;

void compress_files_range(ProcessTask *task, const char *temp_file) {
    FILE *temp = fopen(temp_file, "wb");
    if (!temp) exit(1);
    
    for (int i = task->start; i < task->end; i++) {
        char full_path[MAX_PATH];
        snprintf(full_path, sizeof(full_path), "%s/%s", task->dir_path, task->files[i]);
        
        FILE *f = fopen(full_path, "rb");
        if (!f) continue;
        
        fseek(f, 0, SEEK_END);
        unsigned long orig_size = ftell(f);
        fseek(f, 0, SEEK_SET);
        
        unsigned char *data = malloc(orig_size);
        fread(data, 1, orig_size, f);
        fclose(f);
        
        unsigned long comp_size;
        unsigned char *compressed = compress_data(data, orig_size, task->table, &comp_size);
        free(data);
        
        uint16_t name_len = strlen(task->files[i]);
        fwrite(&name_len, 2, 1, temp);
        fwrite(task->files[i], 1, name_len, temp);
        
        uint32_t orig_size_be = orig_size;
        uint32_t comp_size_be = comp_size;
        fwrite(&orig_size_be, 4, 1, temp);
        fwrite(&comp_size_be, 4, 1, temp);
        fwrite(compressed, 1, comp_size, temp);
        
        free(compressed);
    }
    
    fclose(temp);
    exit(0);
}

int compress_directory_fork(const char *dir_path, const char *output_file, int num_procs) {
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
    
    int files_per_proc = file_count / num_procs;
    int remainder = file_count % num_procs;
    
    pid_t pids[num_procs];
    int start = 0;
    
    printf("Step 5: Compressing with %d processes...\n", num_procs);
    long long start_time = get_time_ms();
    
    for (int i = 0; i < num_procs; i++) {
        int end = start + files_per_proc + (i < remainder ? 1 : 0);
        
        pids[i] = fork();
        
        if (pids[i] == 0) {
            char temp_name[64];
            snprintf(temp_name, sizeof(temp_name), "temp_%d_%d.bin", getpid(), i);
            
            ProcessTask task = {
                .files = file_list,
                .start = start,
                .end = end,
                .dir_path = (char*)dir_path,
                .table = table
            };
            
            compress_files_range(&task, temp_name);
        }
        
        start = end;
    }
    
    for (int i = 0; i < num_procs; i++) {
        waitpid(pids[i], NULL, 0);
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
    
    start = 0;
    for (int i = 0; i < num_procs; i++) {
        int end = start + files_per_proc + (i < remainder ? 1 : 0);
        
        char temp_name[64];
        snprintf(temp_name, sizeof(temp_name), "temp_%d_%d.bin", pids[i], i);
        
        FILE *temp = fopen(temp_name, "rb");
        if (temp) {
            char buffer[BUFFER_SIZE];
            size_t bytes;
            while ((bytes = fread(buffer, 1, sizeof(buffer), temp)) > 0) {
                fwrite(buffer, 1, bytes, out);
            }
            fclose(temp);
            remove(temp_name);
        }
        
        start = end;
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
        fprintf(stderr, "Usage: %s <input_directory> <output_file> <num_processes>\n", argv[0]);
        return 1;
    }
    
    int num_procs = atoi(argv[3]);
    if (num_procs < 1) num_procs = 1;
    
    return compress_directory_fork(argv[1], argv[2], num_procs);
}
