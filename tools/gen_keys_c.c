#include <oqs/oqs.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "Usage: %s <pubkey.bin> <seckey.bin>\n", argv[0]); return 2; }
  OQS_SIG *s = OQS_SIG_new(OQS_SIG_alg_dilithium_2);
  if (!s) { fprintf(stderr, "OQS_SIG_new failed\n"); return 1; }
  uint8_t *pk = malloc(s->length_public_key);
  uint8_t *sk = malloc(s->length_secret_key);
  if (!pk || !sk) { fprintf(stderr, "malloc failed\n"); return 1; }
  if (OQS_SIG_keypair(s, pk, sk) != OQS_SUCCESS) { fprintf(stderr, "keypair failed\n"); return 1; }
  FILE *fp = fopen(argv[1], "wb"); if (!fp) { perror("pubkey"); return 1; }
  fwrite(pk, 1, s->length_public_key, fp); fclose(fp);
  fp = fopen(argv[2], "wb"); if (!fp) { perror("seckey"); return 1; }
  fwrite(sk, 1, s->length_secret_key, fp); fclose(fp);
  printf("Wrote pk=%zu, sk=%zu\n", (size_t)s->length_public_key, (size_t)s->length_secret_key);
  free(pk); free(sk); OQS_SIG_free(s); return 0;
}
