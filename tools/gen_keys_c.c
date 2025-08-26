#include <oqs/oqs.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void shake256(const unsigned char *in, size_t inlen,
                     unsigned char *out, size_t outlen) {
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    EVP_DigestInit_ex(ctx, EVP_shake256(), NULL);
    EVP_DigestUpdate(ctx, in, inlen);
    EVP_DigestFinalXOF(ctx, out, outlen);
    EVP_MD_CTX_free(ctx);
}

static void crh_pk(const unsigned char *pk, size_t pklen, unsigned char out48[48]) {
    shake256(pk, pklen, out48, 48);
}

static int hex2bin(const char *hex, unsigned char *out, size_t outlen) {
    for (size_t i = 0; i < outlen; i++) {
        unsigned int b;
        if (sscanf(hex + 2 * i, "%2x", &b) != 1) {
            return -1;  // bad hex input
        }
        out[i] = (unsigned char)b;
    }
    return 0;
}

static void bin2hex(const unsigned char *b, size_t n, FILE *f) {
    for (size_t i = 0; i < n; i++) fprintf(f, "%02x", b[i]);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <pub_out> <sec_out> [--seed HEX64]\n", argv[0]);
        return 1;
    }
    const char *pub_path = argv[1], *sec_path = argv[2];

    // seed
    unsigned char seed[32];
    if (argc == 5 && strcmp(argv[3], "--seed") == 0 && strlen(argv[4]) == 64) {
        if (hex2bin(argv[4], seed, 32) != 0) {
            fprintf(stderr, "Bad seed hex\n");
            return 2;
        }
    } else {
        FILE *ur = fopen("/dev/urandom", "rb");
        if (!ur) { perror("urandom"); return 3; }
        if (fread(seed, 1, 32, ur) != 32) {
            fclose(ur);
            fprintf(stderr, "urandom short read\n");
            return 3;
        }
        fclose(ur);
    }

    // derive rho, rhoprime, K via simple domain tags
    unsigned char in[33];
    in[0] = 0x00; memcpy(in + 1, seed, 32);
    unsigned char rho[32], rhoprime[32], K[32], tr[48];
    shake256(in, 33, rho, 32);
    in[0] = 0x01; shake256(in, 33, rhoprime, 32);
    in[0] = 0x02; shake256(in, 33, K, 32);

    // liboqs keypair (pk/sk sizes remain 1312/2528 for Dilithium-II)
    OQS_SIG *alg = OQS_SIG_new(OQS_SIG_alg_dilithium_2);
    if (!alg) { fprintf(stderr, "OQS init failed\n"); return 4; }
    unsigned char *pk = (unsigned char *)malloc(alg->length_public_key);
    unsigned char *sk = (unsigned char *)malloc(alg->length_secret_key);
    if (!pk || !sk) { fprintf(stderr, "malloc failed\n"); OQS_SIG_free(alg); return 5; }
    if (OQS_SIG_keypair(alg, pk, sk) != OQS_SUCCESS) {
        fprintf(stderr, "keypair failed\n");
        free(pk); free(sk); OQS_SIG_free(alg);
        return 6;
    }

    // tr = CRH(pk) 48B
    crh_pk(pk, alg->length_public_key, tr);

    // write outputs
    FILE *fp = fopen(pub_path, "wb"); if (!fp) { perror(pub_path); return 7; }
    fwrite(pk, 1, alg->length_public_key, fp); fclose(fp);

    fp = fopen(sec_path, "wb"); if (!fp) { perror(sec_path); return 7; }
    fwrite(sk, 1, alg->length_secret_key, fp); fclose(fp);

    fp = fopen("out/tr.bin", "wb"); if (!fp) { perror("out/tr.bin"); return 7; }
    fwrite(tr, 1, 48, fp); fclose(fp);

    fp = fopen("out/keymeta.txt", "w"); if (!fp) { perror("out/keymeta.txt"); return 7; }
    fprintf(fp, "seed=");      bin2hex(seed, 32, fp);      fprintf(fp, "\n");
    fprintf(fp, "rho=");       bin2hex(rho, 32, fp);       fprintf(fp, "\n");
    fprintf(fp, "rho_prime="); bin2hex(rhoprime, 32, fp);  fprintf(fp, "\n");
    fprintf(fp, "K=");         bin2hex(K, 32, fp);         fprintf(fp, "\n");
    fprintf(fp, "tr=");        bin2hex(tr, 48, fp);        fprintf(fp, "\n");
    fclose(fp);

    OQS_SIG_free(alg); free(pk); free(sk);
    printf("Wrote pk=%zu, sk=%zu, tr=48\n", (size_t)1312, (size_t)2528);
    return 0;
}
