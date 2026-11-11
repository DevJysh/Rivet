/* The part of Rivet that Goose's os module does not cover: streaming copies,
   chmod, a subprocess, and a tree removal that never follows symbolic links.

   A Goose `u8[:]` crosses into C as { data, len } (spec 24, extern fn), which
   is the layout of rv_str below, so these functions take slices by value.
   Slices are not NUL-terminated, so each path is copied to a C string first. */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { const uint8_t *data; int64_t len; } rv_str;

#define RV_COPY_BUF (1 << 20)

/* A NUL-terminated copy of s, or NULL when memory runs out. */
static char *rv_cpath(rv_str s) {
    char *p = malloc((size_t)s.len + 1);
    if (!p) return NULL;
    if (s.len > 0) memcpy(p, s.data, (size_t)s.len);
    p[s.len] = '\0';
    return p;
}

/* What is at path, without following a symbolic link at the end:
   0 missing, 1 regular file, 2 directory, 3 symbolic link, 4 other. */
int32_t rv_kind(rv_str path) {
    char *p = rv_cpath(path);
    struct stat st;
    int32_t kind = 0;
    if (!p) return 0;
    if (lstat(p, &st) == 0) {
        if (S_ISREG(st.st_mode)) kind = 1;
        else if (S_ISDIR(st.st_mode)) kind = 2;
        else if (S_ISLNK(st.st_mode)) kind = 3;
        else kind = 4;
    }
    free(p);
    return kind;
}

/* Size of the file at path, following links; -1 when there is none. */
int64_t rv_file_size(rv_str path) {
    char *p = rv_cpath(path);
    struct stat st;
    int64_t size = -1;
    if (!p) return -1;
    if (stat(p, &st) == 0 && S_ISREG(st.st_mode)) size = (int64_t)st.st_size;
    free(p);
    return size;
}

/* The first four bytes of the file as a little-endian word, or -1. */
int64_t rv_file_magic(rv_str path) {
    char *p = rv_cpath(path);
    unsigned char b[4];
    int64_t word = -1;
    int fd;
    if (!p) return -1;
    fd = open(p, O_RDONLY);
    free(p);
    if (fd < 0) return -1;
    if (read(fd, b, 4) == 4)
        word = (int64_t)((uint32_t)b[0] | (uint32_t)b[1] << 8 |
                         (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24);
    close(fd);
    return word;
}

/* 2 for a type 2 AppImage, 1 for type 1, 0 for anything else. An AppImage is
   an ELF file with the bytes 'A' 'I' and its type at offset 8. Rivet only runs
   a file that passes this check, to extract its icon. */
int32_t rv_appimage_type(rv_str path) {
    char *p = rv_cpath(path);
    unsigned char b[3];
    int32_t type = 0;
    int fd;
    if (!p) return 0;
    fd = open(p, O_RDONLY);
    free(p);
    if (fd < 0) return 0;
    if (pread(fd, b, 3, 8) == 3 && b[0] == 'A' && b[1] == 'I' && (b[2] == 1 || b[2] == 2))
        type = b[2];
    close(fd);
    return type;
}

/* Copies src to dst in pieces, so a large AppImage never sits in memory.
   0 on success, -1 on failure, -2 when src and dst are the same file. The
   source may be a link; the destination may not (O_NOFOLLOW), so a planted
   link cannot redirect the write. */
int32_t rv_copy_file(rv_str src, rv_str dst) {
    char *s = rv_cpath(src), *d = rv_cpath(dst);
    struct stat ss, ds;
    unsigned char *buf = NULL;
    int in = -1, out = -1, rc = -1;
    if (!s || !d) goto done;

    in = open(s, O_RDONLY);
    if (in < 0) goto done;
    if (fstat(in, &ss) != 0 || !S_ISREG(ss.st_mode)) goto done;
    if (stat(d, &ds) == 0 && ds.st_dev == ss.st_dev && ds.st_ino == ss.st_ino) {
        rc = -2;
        goto done;
    }
    out = open(d, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0644);
    if (out < 0) goto done;
    buf = malloc(RV_COPY_BUF);
    if (!buf) goto done;

    for (;;) {
        ssize_t n = read(in, buf, RV_COPY_BUF);
        ssize_t off = 0;
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) goto done;
        if (n == 0) break;
        while (off < n) {
            ssize_t w = write(out, buf + off, (size_t)(n - off));
            if (w < 0 && errno == EINTR) continue;
            if (w < 0) goto done;
            off += w;
        }
    }
    if (close(out) != 0) { out = -1; goto done; }
    out = -1;
    rc = 0;

done:
    if (rc != 0 && out >= 0) { close(out); unlink(d ? d : ""); }
    if (in >= 0) close(in);
    free(buf);
    free(s);
    free(d);
    return rc;
}

int32_t rv_chmod(rv_str path, int32_t mode) {
    char *p = rv_cpath(path);
    int32_t rc;
    if (!p) return -1;
    rc = chmod(p, (mode_t)mode) == 0 ? 0 : -1;
    free(p);
    return rc;
}

/* Runs prog (looked up on PATH) with up to two arguments, in dir when dir is
   not empty, with stdin, stdout and stderr on /dev/null. An empty argument is
   left out. Returns the exit status, 127 when prog cannot start, or -1 when
   no process could be made. */
int32_t rv_run(rv_str dir, rv_str prog, rv_str a1, rv_str a2) {
    char *p = rv_cpath(prog), *d = rv_cpath(dir);
    char *x1 = rv_cpath(a1), *x2 = rv_cpath(a2);
    char *argv[4];
    int argc = 0, status = 0;
    pid_t pid;
    int32_t rc = -1;

    if (!p || !d || !x1 || !x2) goto done;
    argv[argc++] = p;
    if (a1.len > 0) argv[argc++] = x1;
    if (a2.len > 0) argv[argc++] = x2;
    argv[argc] = NULL;

    pid = fork();
    if (pid < 0) goto done;
    if (pid == 0) {
        int null = open("/dev/null", O_RDWR);
        if (null >= 0) {
            dup2(null, 0);
            dup2(null, 1);
            dup2(null, 2);
        }
        if (dir.len > 0 && chdir(d) != 0) _exit(126);
        execvp(p, argv);
        _exit(127);
    }
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) goto done;
    }
    if (WIFEXITED(status)) rc = WEXITSTATUS(status);
    else rc = -1;

done:
    free(p); free(d); free(x1); free(x2);
    return rc;
}

/* Removes path and everything under it. Symbolic links are removed as links
   and never followed, so nothing outside the tree is touched. 0 on success. */
int32_t rv_remove_tree(rv_str path) {
    char *p = rv_cpath(path);
    struct stat st;
    int32_t rc = 0;
    if (!p) return -1;
    if (lstat(p, &st) != 0) { free(p); return 0; }
    if (S_ISDIR(st.st_mode)) {
        DIR *dir = opendir(p);
        struct dirent *e;
        if (!dir) { free(p); return -1; }
        while ((e = readdir(dir)) != NULL) {
            char *child;
            rv_str cs;
            if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
            child = malloc(strlen(p) + strlen(e->d_name) + 2);
            if (!child) { rc = -1; break; }
            snprintf(child, strlen(p) + strlen(e->d_name) + 2, "%s/%s", p, e->d_name);
            cs.data = (const uint8_t *)child;
            cs.len = (int64_t)strlen(child);
            if (rv_remove_tree(cs) != 0) rc = -1;
            free(child);
        }
        closedir(dir);
        if (rmdir(p) != 0) rc = -1;
    } else {
        if (unlink(p) != 0) rc = -1;
    }
    free(p);
    return rc;
}
