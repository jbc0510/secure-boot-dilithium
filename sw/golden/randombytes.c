#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>

static void fill_random(uint8_t *buf, size_t n) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) { perror("open /dev/urandom"); exit(1); }
    size_t off = 0;
    while (off < n) {
        ssize_t r = read(fd, buf + off, n - off);
        if (r <= 0) { perror("read /dev/urandom"); exit(1); }
        off += (size_t)r;
    }
    close(fd);
}

// Some PQClean code calls this:
void PQCLEAN_randombytes(uint8_t *x, size_t xlen) { fill_random(x, xlen); }

// Others call this:
void randombytes(uint8_t *x, size_t xlen) { fill_random(x, xlen); }
