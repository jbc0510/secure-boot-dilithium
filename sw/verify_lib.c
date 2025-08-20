#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>

#ifdef __has_include
#  if __has_include(<oqs/oqs.h>)
#    define HAVE_OQS 1
#    include <oqs/oqs.h>
#  endif
#endif

#include <openssl/evp.h>

static const char *k_domain = "BOOT_FW_V1";
#define DIGEST_LEN 64  // 64 bytes from SHAKE256 XOF

int compute_firmware_digest(const uint8_t* data, size_t len,
                            uint8_t* out_digest, size_t* out_len) {
  if (!out_digest || !out_len || *out_len < DIGEST_LEN) return -1;

  int rc = -2;
  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  if (!ctx) return -3;

  if (EVP_DigestInit_ex(ctx, EVP_shake256(), NULL) != 1) goto out;
  if (EVP_DigestUpdate(ctx, (const uint8_t*)k_domain, strlen(k_domain)) != 1) goto out;
  if (EVP_DigestUpdate(ctx, data, len) != 1) goto out;
  if (EVP_DigestFinalXOF(ctx, out_digest, DIGEST_LEN) != 1) goto out;

  *out_len = DIGEST_LEN;
  rc = 0;
out:
  EVP_MD_CTX_free(ctx);
  return rc;
}

int dilithium_verify_digest(
    const uint8_t *digest, size_t digest_len,
    const uint8_t *sig, size_t sig_len,
    const uint8_t *pk, size_t pk_len) {

    (void)pk_len;  // suppress unused parameter warning
#ifndef HAVE_OQS
  (void)digest; (void)digest_len; (void)sig; (void)sig_len; (void)pk; (void)pk_len;
  return -100;
#else
  OQS_SIG *s = OQS_SIG_new(OQS_SIG_alg_dilithium_2);
  if (!s) return -2;
  OQS_STATUS ok = OQS_SIG_verify(s, digest, digest_len, sig, sig_len, pk);
  OQS_SIG_free(s);
  return (ok == OQS_SUCCESS) ? 0 : -3;
#endif
}
