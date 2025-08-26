#include <openssl/sha.h>
#include <stdio.h>
#include <stdlib.h>

static void sha256_hex(const unsigned char *p, size_t n, char out[65]) {
    unsigned char h[32];
    SHA256(p, n, h);
    for (int i = 0; i < 32; i++) { sprintf(out + 2*i, "%02x", h[i]); }
    out[64] = 0;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "Usage: %s <sec.key> <pub.key>\n", argv[0]); return 1; }

    // load sec.key
    FILE *f = fopen(argv[1], "rb"); if (!f) { perror("sec"); return 2; }
    if (fseek(f, 0, SEEK_END)) { perror("fseek"); return 2; }
    long sklen = ftell(f); if (sklen <= 0) { fprintf(stderr, "bad sec len\n"); return 2; }
    rewind(f);
    unsigned char *sk = malloc(sklen); if (!sk) { fprintf(stderr, "oom\n"); return 2; }
    size_t r = fread(sk, 1, sklen, f); fclose(f);
    if (r != (size_t)sklen) { fprintf(stderr, "short read sec\n"); return 2; }

    // load pub.key (length check only)
    f = fopen(argv[2], "rb"); if (!f) { perror("pub"); return 3; }
    if (fseek(f, 0, SEEK_END)) { perror("fseek"); return 3; }
    long pklen = ftell(f); if (pklen <= 0) { fprintf(stderr, "bad pub len\n"); return 3; }
    fclose(f);

    if (pklen != 1312 || (sklen != 2528 && sklen != 2544)) {
        fprintf(stderr, "[!] Unexpected sizes pk=%ld sk=%ld\n", pklen, sklen);
    }

    // fixed header fields in sec.key
    const size_t off_rho = 0,  len_rho = 32;
    const size_t off_K   = 32, len_K   = 32;
    const size_t off_tr  = 64, len_tr  = 48;

    char H_rho[65], H_K[65], H_tr[65], H_tail[65];
    sha256_hex(sk + off_rho, len_rho, H_rho);
    sha256_hex(sk + off_K,   len_K,   H_K);
    sha256_hex(sk + off_tr,  len_tr,  H_tr);
    size_t tail_off = off_tr + len_tr;
    if (tail_off <= (size_t)sklen) {
        sha256_hex(sk + tail_off, (size_t)sklen - tail_off, H_tail);
    } else {
        H_tail[0] = 0;
    }

    printf("{\"pk_len\":%ld,\"sk_len\":%ld,"
           "\"rho_sha256\":\"%s\",\"K_sha256\":\"%s\",\"tr_sha256\":\"%s\","
           "\"tail_sha256\":\"%s\"}\n",
           pklen, sklen, H_rho, H_K, H_tr, H_tail);

    free(sk);
    return 0;
}
