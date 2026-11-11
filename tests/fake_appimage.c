/* A stand-in for an AppImage, for tests/smoke.sh. It does what the parts of
   the AppImage runtime that Rivet relies on do: `--appimage-extract [pattern]`
   writes ./squashfs-root holding the matching files, and a plain run prints a
   line and exits.

   Environment, set by the test:
     FAKE_NO_ICONS=1   the AppImage has no icons at all
     FAKE_DIRICON_ONLY=1  the only icon is a top-level .DirIcon
     FAKE_TRAP=<dir>   an absolute symlink named evil points at <dir>, which
                       holds a file that must survive the install */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static void mkdirs(const char *path) {
    char buf[4096];
    size_t n = strlen(path);
    for (size_t i = 1; i <= n; i++) {
        if (path[i] == '/' || path[i] == '\0') {
            memcpy(buf, path, i);
            buf[i] = '\0';
            mkdir(buf, 0755);
        }
    }
}

static void write_bytes(const char *path, const char *data, size_t n) {
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fwrite(data, 1, n, f);
    fclose(f);
}

static int wants(const char *pattern, const char *prefix) {
    return pattern == NULL || strncmp(pattern, prefix, strlen(prefix)) == 0;
}

int main(int argc, char **argv) {
    int no_icons = getenv("FAKE_NO_ICONS") != NULL;

    if (argc >= 2 && strcmp(argv[1], "--appimage-extract") == 0) {
        const char *pattern = argc > 2 ? argv[2] : NULL;
        if (no_icons) return 0;
        if (wants(pattern, "usr/share/icons") && !getenv("FAKE_DIRICON_ONLY")) {
            mkdirs("squashfs-root/usr/share/icons/hicolor/256x256/apps");
            mkdirs("squashfs-root/usr/share/icons/hicolor/scalable/apps");
            write_bytes("squashfs-root/usr/share/icons/hicolor/256x256/apps/krita.png",
                        "\x89PNG\r\n\x1a\n", 8);
            write_bytes("squashfs-root/usr/share/icons/hicolor/scalable/apps/krita.svg",
                        "<svg xmlns=\"http://www.w3.org/2000/svg\"/>", 39);
            mkdirs("squashfs-root/usr/share/icons/hicolor/16x16/apps");
            write_bytes("squashfs-root/usr/share/icons/hicolor/16x16/apps/krita.png",
                        "\x89PNG\r\n\x1a\n", 8);
            if (getenv("FAKE_TRAP")) {
                /* A link out of the tree, as real AppImages sometimes carry. */
                mkdirs("squashfs-root/usr/share/icons");
                symlink(getenv("FAKE_TRAP"), "squashfs-root/usr/share/icons/evil");
            }
        }
        if (wants(pattern, ".DirIcon") && pattern != NULL) {
            mkdirs("squashfs-root");
            write_bytes("squashfs-root/.DirIcon", "\x89PNG\r\n\x1a\n", 8);
        }
        return 0;
    }

    printf("fake app running\n");
    return 0;
}
