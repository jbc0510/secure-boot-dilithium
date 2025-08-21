// tools/sign_fw_c.c — build header with fw_header_t from image_format.h
#include <oqs/oqs.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "image_format.h"   // <- brings fw_header_t, HDR_MAGIC, HDR_SIZE, D2_* and HDR_BLOB_OFFSET

static const char *k_domain = "BOOT_FW_V1";
#define DIGEST_LEN 64

static int read_all(const char *path, uint8_t **buf, size_t *len) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -2; }
  long n = ftell(f); if (n < 0) { fclose(f); return -3; }
  if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -4; }
  *buf = (uint8_t*)malloc((size_t)n);
  if (!*buf) { fclose(f); return -5; }
  if (fread(*buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(*buf); return -6; }
  fclose(f);
  *len = (size_t)n;
  return 0;
}

static int write_all(const char *path, const uint8_t *buf, size_t len) {
  FILE *f = fopen(path, "wb"); if (!f) return -1;
  if (fwrite(buf, 1, len, f) != len) { fclose(f); return -2; }
  fclose(f); return 0;
}

static int shake256_digest(const uint8_t *payload, size_t plen,
                           uint8_t *out, size_t outlen) {
  int rc = -1;
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  if (!ctx) return -2;
  if (EVP_DigestInit_ex(ctx, EVP_shake256(), NULL) != 1) goto out;
  if (EVP_DigestUpdate(ctx, (const uint8_t*)k_domain, strlen(k_domain)) != 1) goto out;
  if (EVP_DigestUpdate(ctx, payload, plen) != 1) goto out;
  if (EVP_DigestFinalXOF(ctx, out, outlen) != 1) goto out;
  rc = 0;
out:
  EVP_MD_CTX_free(ctx);
  return rc;
}

int main(int argc, char **argv) {
  // Usage: sign_fw_c <fw_payload.bin> <pubkey.bin> <seckey.bin> <version> <out_header>
  if (argc != 6) {
    fprintf(stderr, "Usage: %s <fw_payload.bin> <pubkey.bin> <seckey.bin> <version> <out_header>\n", argv[0]);
    return 2;
  }
  const char *fw_path = argv[1];
  const char *pk_path = argv[2];
  const char *sk_path = argv[3];
  unsigned long version = strtoul(argv[4], NULL, 0);
  const char *out_hdr = argv[5];

  uint8_t *fw=NULL, *pk=NULL, *sk=NULL;
  size_t fw_len=0, pk_len=0, sk_len=0;
  if (read_all(fw_path, &fw, &fw_len) ||
      read_all(pk_path, &pk, &pk_len) ||
      read_all(sk_path, &sk, &sk_len)) {
    fprintf(stderr, "[-] read inputs failed\n");
    return 1;
  }

  // Enforce Dilithium‑2 lengths in the tool as well
  if (pk_len != D2_PK_LEN) {
    fprintf(stderr, "[-] pubkey length mismatch: got %zu, expected %d\n", pk_len, D2_PK_LEN);
    return 1;
  }

  uint8_t digest[DIGEST_LEN];
  if (shake256_digest(fw, fw_len, digest, DIGEST_LEN) != 0) {
    fprintf(stderr, "[-] digest failed\n");
    return 1;
  }

  OQS_SIG *s = OQS_SIG_new(OQS_SIG_alg_dilithium_2);
  if (!s) { fprintf(stderr, "OQS_SIG_new failed\n"); return 1; }

  size_t sig_len = s->length_signature;
  if ((int)sig_len != D2_SIG_LEN) {
    fprintf(stderr, "[-] signer reports sig_len=%zu, expected %d\n", sig_len, D2_SIG_LEN);
    OQS_SIG_free(s);
    return 1;
  }

  uint8_t *sig = (uint8_t*)malloc(sig_len);
  if (!sig) { fprintf(stderr, "malloc sig failed\n"); OQS_SIG_free(s); return 1; }

  if (OQS_SIG_sign(s, sig, &sig_len, digest, DIGEST_LEN, sk) != OQS_SUCCESS) {
    fprintf(stderr, "[-] sign failed\n");
    free(sig); OQS_SIG_free(s);
    return 1;
  }

  // Build header using fw_header_t and HDR_BLOB_OFFSET
  uint8_t header[HDR_SIZE];
  memset(header, 0, sizeof(header));

  fw_header_t h = {
    .magic       = HDR_MAGIC,
    .header_size = HDR_SIZE,
    .version     = (uint32_t)version,
    .fw_size     = (uint32_t)fw_len,
    .pk_len      = (uint32_t)pk_len,
    .sig_len     = (uint32_t)sig_len
  };

  // Copy fixed struct first
  memcpy(header, &h, sizeof(h));

  // Copy pk||sig at defined blob offset
  if ((size_t)HDR_BLOB_OFFSET + pk_len + sig_len > (size_t)HDR_SIZE) {
    fprintf(stderr, "[-] header too small for pk+sig (need %zu)\n",
            (size_t)HDR_BLOB_OFFSET + pk_len + sig_len);
    free(sig); OQS_SIG_free(s); free(fw); free(pk); free(sk);
    return 1;
  }
  memcpy(header + HDR_BLOB_OFFSET, pk, pk_len);
  memcpy(header + HDR_BLOB_OFFSET + pk_len, sig, sig_len);

  if (write_all(out_hdr, header, sizeof(header)) != 0) {
    fprintf(stderr, "[-] write header failed\n");
    free(sig); OQS_SIG_free(s); free(fw); free(pk); free(sk);
    return 1;
  }

  fprintf(stdout, "[+] header written: %s (pk=%zu, sig=%zu, fw=%zu, ver=%lu)\n",
          out_hdr, pk_len, sig_len, fw_len, version);

  free(sig); OQS_SIG_free(s);
  free(fw); free(pk); free(sk);
  return 0;
}
