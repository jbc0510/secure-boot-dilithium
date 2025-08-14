#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// Use the exact PQClean header for ML-DSA-44
#include "ext/pqclean/crypto_sign/ml-dsa-44/clean/api.h"

// Convenience aliases in case generic macros aren't provided
#ifndef CRYPTO_PUBLICKEYBYTES
#define CRYPTO_PUBLICKEYBYTES PQCLEAN_MLDSA44_CLEAN_CRYPTO_PUBLICKEYBYTES
#endif
#ifndef CRYPTO_SECRETKEYBYTES
#define CRYPTO_SECRETKEYBYTES PQCLEAN_MLDSA44_CLEAN_CRYPTO_SECRETKEYBYTES
#endif
#ifndef CRYPTO_BYTES
#define CRYPTO_BYTES PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES
#endif

static void usage(const char *p) {
    fprintf(stderr,
      "Usage:\n"
      "  %s genkey <pubkey.bin> <seckey.bin>\n"
      "  %s sign <pubkey.bin> <seckey.bin> <firmware.bin> <signature.bin>\n",
      p, p);
    exit(1);
}

int main(int argc, char **argv) {
    if (argc < 2) usage(argv[0]);

    if (strcmp(argv[1], "genkey") == 0) {
        if (argc != 4) usage(argv[0]);
        uint8_t pk[CRYPTO_PUBLICKEYBYTES];
        uint8_t sk[CRYPTO_SECRETKEYBYTES];
        if (PQCLEAN_MLDSA44_CLEAN_crypto_sign_keypair(pk, sk) != 0) {
            fprintf(stderr,"keypair failed\n"); return 2;
        }
        FILE *fpk = fopen(argv[2], "wb"); if (!fpk) { perror("pubkey"); return 3; }
        FILE *fsk = fopen(argv[3], "wb"); if (!fsk) { perror("seckey"); fclose(fpk); return 3; }
        if (fwrite(pk, 1, sizeof pk, fpk) != sizeof pk) { perror("write pk"); return 4; }
        if (fwrite(sk, 1, sizeof sk, fsk) != sizeof sk) { perror("write sk"); return 4; }
        fclose(fpk); fclose(fsk);
        return 0;
    }

    if (strcmp(argv[1], "sign") == 0) {
        if (argc != 6) usage(argv[0]);

        uint8_t pk[CRYPTO_PUBLICKEYBYTES];
        uint8_t sk[CRYPTO_SECRETKEYBYTES];

        FILE *fpk = fopen(argv[2], "rb"); if (!fpk) { perror("pubkey"); return 3; }
        FILE *fsk = fopen(argv[3], "rb"); if (!fsk) { perror("seckey"); fclose(fpk); return 3; }
        if (fread(pk, 1, sizeof pk, fpk) != sizeof pk) { fprintf(stderr,"bad pk size\n"); return 4; }
        if (fread(sk, 1, sizeof sk, fsk) != sizeof sk) { fprintf(stderr,"bad sk size\n"); return 4; }
        fclose(fpk); fclose(fsk);

        FILE *ffin = fopen(argv[4], "rb"); if (!ffin) { perror("firmware"); return 3; }
        if (fseek(ffin, 0, SEEK_END) != 0) { perror("seek"); return 3; }
        long flen = ftell(ffin); if (flen < 0) { perror("ftell"); return 3; }
        rewind(ffin);
        uint8_t *msg = (uint8_t*)malloc((size_t)flen); if (!msg) { fprintf(stderr,"oom\n"); return 5; }
        if (fread(msg, 1, (size_t)flen, ffin) != (size_t)flen) { fprintf(stderr,"read msg\n"); return 4; }
        fclose(ffin);

        uint8_t sig[CRYPTO_BYTES];
        size_t siglen = 0;
        if (PQCLEAN_MLDSA44_CLEAN_crypto_sign_signature(sig, &siglen, msg, (size_t)flen, sk) != 0) {
            fprintf(stderr,"sign failed\n"); free(msg); return 6;
        }

        FILE *fsig = fopen(argv[5], "wb"); if (!fsig) { perror("signature"); free(msg); return 3; }
        if (fwrite(sig, 1, siglen, fsig) != siglen) { fprintf(stderr,"write sig\n"); return 4; }
        fclose(fsig);
        free(msg);
        (void)pk;
        return 0;
    }

    usage(argv[0]);
    return 0;
}
