#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#define PLUGINS_DIR "/userdisk/PenMods/plugins"
#define STAGING_DIR "/userdisk/PenMods/plugins/.plugin-installer-staging"

typedef struct Metadata {
    char id[128];
    char name[128];
    char version[64];
} Metadata;

static void usage(void)
{
    puts("penmods-plugin install <zip-or-folder>");
    puts("penmods-plugin inspect <zip-or-folder>");
    puts("penmods-plugin list");
}

static int is_dir(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_file(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int path_join(char *out, size_t out_size, const char *left, const char *right)
{
    int written = snprintf(out, out_size, "%s/%s", left, right);
    return written > 0 && (size_t)written < out_size;
}

static int has_metadata(const char *path)
{
    char metadata_path[PATH_MAX];
    return path_join(metadata_path, sizeof(metadata_path), path, "metadata.json")
        && is_file(metadata_path);
}

static int read_file(const char *path, char **out)
{
    FILE *file = fopen(path, "rb");
    long size;
    char *buffer;

    if (!file) {
        return 0;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return 0;
    }
    size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return 0;
    }
    buffer = (char *)calloc((size_t)size + 1, 1);
    if (!buffer) {
        fclose(file);
        return 0;
    }
    if (fread(buffer, 1, (size_t)size, file) != (size_t)size) {
        free(buffer);
        fclose(file);
        return 0;
    }
    fclose(file);
    *out = buffer;
    return 1;
}

static void json_string_value(const char *json, const char *key, char *out, size_t out_size)
{
    char pattern[96];
    const char *pos;
    const char *start;
    size_t i = 0;

    out[0] = '\0';
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    pos = strstr(json, pattern);
    if (!pos) {
        return;
    }
    pos = strchr(pos + strlen(pattern), ':');
    if (!pos) {
        return;
    }
    start = strchr(pos, '"');
    if (!start) {
        return;
    }
    start++;
    while (*start && *start != '"' && i + 1 < out_size) {
        out[i++] = *start++;
    }
    out[i] = '\0';
}

static int read_metadata(const char *plugin_root, Metadata *metadata)
{
    char metadata_path[PATH_MAX];
    char *json = NULL;

    memset(metadata, 0, sizeof(*metadata));
    if (!path_join(metadata_path, sizeof(metadata_path), plugin_root, "metadata.json")
        || !read_file(metadata_path, &json)) {
        fprintf(stderr, "error: metadata.json not found in %s\n", plugin_root);
        return 0;
    }

    json_string_value(json, "id", metadata->id, sizeof(metadata->id));
    json_string_value(json, "name", metadata->name, sizeof(metadata->name));
    json_string_value(json, "version", metadata->version, sizeof(metadata->version));
    free(json);

    if (metadata->id[0] == '\0') {
        fprintf(stderr, "error: metadata.json does not contain plugin id\n");
        return 0;
    }
    return 1;
}

static int find_plugin_root(const char *path, char *out, size_t out_size)
{
    DIR *dir;
    struct dirent *entry;
    int count = 0;
    char candidate[PATH_MAX];

    if (has_metadata(path)) {
        snprintf(out, out_size, "%s", path);
        return 1;
    }

    dir = opendir(path);
    if (!dir) {
        return 0;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        if (!path_join(candidate, sizeof(candidate), path, entry->d_name)) {
            continue;
        }
        if (is_dir(candidate) && has_metadata(candidate)) {
            snprintf(out, out_size, "%s", candidate);
            count++;
        }
    }
    closedir(dir);

    if (count == 1) {
        return 1;
    }
    fprintf(stderr, "error: %s plugin roots found in %s\n", count == 0 ? "no" : "multiple", path);
    return 0;
}

static int ends_with_zip(const char *path)
{
    size_t len = strlen(path);
    return len > 4
        && tolower((unsigned char)path[len - 4]) == '.'
        && tolower((unsigned char)path[len - 3]) == 'z'
        && tolower((unsigned char)path[len - 2]) == 'i'
        && tolower((unsigned char)path[len - 1]) == 'p';
}

static void shell_quote(char *out, size_t out_size, const char *path)
{
    size_t i = 0;
    if (i + 1 < out_size) {
        out[i++] = '\'';
    }
    while (*path && i + 5 < out_size) {
        if (*path == '\'') {
            memcpy(out + i, "'\\''", 4);
            i += 4;
        } else {
            out[i++] = *path;
        }
        path++;
    }
    if (i + 1 < out_size) {
        out[i++] = '\'';
    }
    out[i] = '\0';
}

static int prepare_source(const char *source, char *root, size_t root_size)
{
    char quoted_source[PATH_MAX * 2];
    char quoted_staging[PATH_MAX * 2];
    char command[PATH_MAX * 5];

    if (is_dir(source)) {
        return find_plugin_root(source, root, root_size);
    }
    if (!is_file(source) || !ends_with_zip(source)) {
        fprintf(stderr, "error: source must be a plugin folder or .zip package\n");
        return 0;
    }

    shell_quote(quoted_source, sizeof(quoted_source), source);
    shell_quote(quoted_staging, sizeof(quoted_staging), STAGING_DIR);
    snprintf(command, sizeof(command), "rm -rf %s && mkdir -p %s && unzip -q -o %s -d %s",
        quoted_staging, quoted_staging, quoted_source, quoted_staging);
    if (system(command) != 0) {
        fprintf(stderr, "error: failed to extract zip package; is unzip available?\n");
        return 0;
    }
    return find_plugin_root(STAGING_DIR, root, root_size);
}

static void folder_name_for_id(const char *id, char *out, size_t out_size)
{
    const char *input = id;
    size_t i = 0;

    if (strncmp(input, "com.", 4) == 0 || strncmp(input, "org.", 4) == 0) {
        input += 4;
    }
    while (*input && i + 1 < out_size) {
        unsigned char ch = (unsigned char)*input++;
        out[i++] = (isalnum(ch) ? (char)tolower(ch) : '_');
    }
    out[i] = '\0';
}

static int copy_dir_atomic(const char *source, const char *target)
{
    char new_target[PATH_MAX];
    char backup_target[PATH_MAX];
    char q_source[PATH_MAX * 2];
    char q_new[PATH_MAX * 2];
    char q_target[PATH_MAX * 2];
    char q_backup[PATH_MAX * 2];
    char command[PATH_MAX * 6];

    snprintf(new_target, sizeof(new_target), "%s.new", target);
    snprintf(backup_target, sizeof(backup_target), "%s.bak", target);
    shell_quote(q_source, sizeof(q_source), source);
    shell_quote(q_new, sizeof(q_new), new_target);
    shell_quote(q_target, sizeof(q_target), target);
    shell_quote(q_backup, sizeof(q_backup), backup_target);

    snprintf(command, sizeof(command), "rm -rf %s && cp -a %s %s", q_new, q_source, q_new);
    if (system(command) != 0) {
        fprintf(stderr, "error: failed to copy plugin into staging target\n");
        return 0;
    }

    snprintf(command, sizeof(command),
        "rm -rf %s && if [ -e %s ]; then mv %s %s; fi && mv %s %s",
        q_backup, q_target, q_target, q_backup, q_new, q_target);
    if (system(command) != 0) {
        snprintf(command, sizeof(command), "rm -rf %s && if [ -e %s ]; then mv %s %s; fi",
            q_target, q_backup, q_backup, q_target);
        system(command);
        fprintf(stderr, "error: failed to replace plugin; rolled back if possible\n");
        return 0;
    }

    snprintf(command, sizeof(command), "rm -rf %s", q_backup);
    system(command);
    return 1;
}

static int inspect_source(const char *source)
{
    char root[PATH_MAX];
    Metadata metadata;

    if (!prepare_source(source, root, sizeof(root)) || !read_metadata(root, &metadata)) {
        return 2;
    }
    printf("id: %s\n", metadata.id);
    if (metadata.name[0]) {
        printf("name: %s\n", metadata.name);
    }
    if (metadata.version[0]) {
        printf("version: %s\n", metadata.version);
    }
    printf("root: %s\n", root);
    return 0;
}

static int install_source(const char *source)
{
    char root[PATH_MAX];
    char folder[128];
    char target[PATH_MAX];
    Metadata metadata;

    if (!prepare_source(source, root, sizeof(root)) || !read_metadata(root, &metadata)) {
        return 2;
    }
    folder_name_for_id(metadata.id, folder, sizeof(folder));
    if (!path_join(target, sizeof(target), PLUGINS_DIR, folder)) {
        fprintf(stderr, "error: target path is too long\n");
        return 2;
    }
    if (!copy_dir_atomic(root, target)) {
        return 2;
    }
    printf("installed %s to %s\n", metadata.id, target);
    return 0;
}

static int list_installed(void)
{
    DIR *dir = opendir(PLUGINS_DIR);
    struct dirent *entry;

    if (!dir) {
        return 0;
    }
    while ((entry = readdir(dir)) != NULL) {
        char path[PATH_MAX];
        Metadata metadata;
        if (entry->d_name[0] == '.') {
            continue;
        }
        if (!path_join(path, sizeof(path), PLUGINS_DIR, entry->d_name) || !is_dir(path) || !has_metadata(path)) {
            continue;
        }
        if (read_metadata(path, &metadata)) {
            printf("%s\t%s\n", metadata.id, path);
        }
    }
    closedir(dir);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        usage();
        return 1;
    }
    if (strcmp(argv[1], "install") == 0 && argc == 3) {
        return install_source(argv[2]);
    }
    if (strcmp(argv[1], "inspect") == 0 && argc == 3) {
        return inspect_source(argv[2]);
    }
    if (strcmp(argv[1], "list") == 0 && argc == 2) {
        return list_installed();
    }
    usage();
    return 1;
}
