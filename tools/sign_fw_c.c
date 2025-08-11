#include <oqs/oqs.h>
#include <openssl/evp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HDR_MAGIC 0x44494C49u   /* 'DILI' */
#define HDR_SIZE  4096u         /* must match rom/image_format.h */

static const char *k_domain = "BOOT_FW_V1";
#define DIGEST_LEN 64

static int read_all(const char *path, uint8_t **buf, size_t *len) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  fseek(f, 0, SEEK_END);
  long n = ftell(f); if (n < 0) { fclose(f); return -2; }
  fseek(f, 0, SEEK_SET);
  *buf = (uint8_t*)malloc((size_t)n);
  if (!*buf) { fclose(f); return -3; }
  if (fread(*buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(*buf); return -4; }
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
  if (read_all(fw_path, &fw, &fw_len) || read_all(pk_path, &pk, &pk_len) || read_all(sk_path, &sk, &sk_len)) {
    fprintf(stderr, "[-] read inputs failed\n"); return 1;
  }

  uint8_t digest[DIGEST_LEN];
  if (shake256_digest(fw, fw_len, digest, DIGEST_LEN) != 0) {
    fprintf(stderr, "[-] digest failed\n"); return 1;
  }

  OQS_SIG *s = OQS_SIG_new(OQS_SIG_alg_dilithium_2);
  if (!s) { fprintf(stderr, "OQS_SIG_new failed\n"); return 1; }

  size_t sig_len = s->length_signature;
  uint8_t *sig = (uint8_t*)malloc(sig_len);
  if (!sig) { fprintf(stderr, "malloc sig failed\n"); return 1; }

  if (OQS_SIG_sign(s, sig, &sig_len, digest, DIGEST_LEN, sk) != OQS_SUCCESS) {
    fprintf(stderr, "[-] sign failed\n"); return 1;
  }

  /* Build header: magic, hdr_size, version, fw_size, pk_len, sig_len, then pk||sig, padded to HDR_SIZE */
  uint8_t header[HDR_SIZE];
  memset(header, 0, sizeof(header));

  uint32_t *u = (uint32_t*)header; /* little-endian host assumption is fine for tooling */
  u[0] = HDR_MAGIC;
  u[1] = HDR_SIZE;
  u[2] = (uint32_t)version;
  u[3] = (uint32_t)fw_len;
  u[4] = (uint32_t)pk_len;
  u[5] = (uint32_t)sig_len;

  size_t blob_off = 0x18;
  if (blob_off + pk_len + sig_len > HDR_SIZE) {
    fprintf(stderr, "[-] header too small for pk+sig (need %zu)\n", blob_off+pk_len+sig_len);
    return 1;
  }
  memcpy(header + blob_off, pk, pk_len);
  memcpy(header + blob_off + pk_len, sig, sig_len);

  if (write_all(out_hdr, header, sizeof(header)) != 0) {
    fprintf(stderr, "[-] write header failed\n"); return 1;
  }

  fprintf(stdout, "[+] header written: %s (pk=%zu, sig=%zu, fw=%zu, ver=%lu)\n",
          out_hdr, pk_len, sig_len, fw_len, version);

  free(sig); OQS_SIG_free(s);
  free(fw); free(pk); free(sk);
  return 0;
}
