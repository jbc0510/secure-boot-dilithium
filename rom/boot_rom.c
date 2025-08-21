// rom/boot_rom.c — A/B slots, PK-hash binding, Dilithium verify, OTP counter (color, strict sizes)

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "otp_pk.h"
#include "image_format.h"
#include <openssl/evp.h>

#define C_RED "\x1b[31m"
#define C_GRN "\x1b[32m"
#define C_YEL "\x1b[33m"
#define C_RST "\x1b[0m"

// If not already defined in image_format.h, enforce Dilithium‑2 lengths here.
#ifndef D2_PK_LEN
#define D2_PK_LEN 1312
#endif
#ifndef D2_SIG_LEN
#define D2_SIG_LEN 2420
#endif

#define OTP_PK_HASH (OTP_PK_HASHES[0])

// --- Protos from sw/verify_lib.c ---
int dilithium_verify_digest(const uint8_t* digest, size_t digest_len,
                            const uint8_t* sig, size_t sig_len,
                            const uint8_t* pk,  size_t pk_len);

// --- Helpers ---
static int load_file(const char* path, uint8_t** out, size_t* out_len) {
  FILE* f = fopen(path, "rb");
  if (!f) return -1;
  if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -2; }
  long n = ftell(f);
  if (n <= 0) { fclose(f); return -3; }
  if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return -4; }
  *out = (uint8_t*)malloc((size_t)n);
  if (!*out) { fclose(f); return -5; }
  if (fread(*out, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(*out); return -6; }
  fclose(f);
  *out_len = (size_t)n;
  return 0;
}

// SHA-256 (for PK binding)
static int sha256(const uint8_t* in, size_t inlen, uint8_t out[32]) {
  unsigned int olen = 0;
  EVP_MD_CTX* c = EVP_MD_CTX_new(); if (!c) return -1;
  if (EVP_DigestInit_ex(c, EVP_sha256(), NULL) != 1) { EVP_MD_CTX_free(c); return -1; }
  if (EVP_DigestUpdate(c, in, inlen) != 1)           { EVP_MD_CTX_free(c); return -1; }
  if (EVP_DigestFinal_ex(c, out, &olen) != 1 || olen != 32) { EVP_MD_CTX_free(c); return -1; }
  EVP_MD_CTX_free(c); return 0;
}

// Firmware digest: SHAKE-256("BOOT_FW_V1" || payload) → 64 bytes
static int fw_digest(const uint8_t* data, size_t len, uint8_t out[64]) {
  EVP_MD_CTX* c = EVP_MD_CTX_new(); if (!c) return -1;
  if (EVP_DigestInit_ex(c, EVP_shake256(), NULL) != 1) { EVP_MD_CTX_free(c); return -1; }
  const char dom[] = "BOOT_FW_V1";
  if (EVP_DigestUpdate(c, dom, sizeof(dom)-1) != 1)    { EVP_MD_CTX_free(c); return -1; }
  if (EVP_DigestUpdate(c, data, len) != 1)             { EVP_MD_CTX_free(c); return -1; }
  int ok = EVP_DigestFinalXOF(c, out, 64) == 1;
  EVP_MD_CTX_free(c);
  return ok ? 0 : -1;
}

// --- Monotonic OTP counter stored in out/otp_counter.bin ---
static uint32_t otp_read(void){
  FILE* f = fopen("out/otp_counter.bin","rb");
  if (!f) return 1;
  uint32_t v = 1;
  if (fread(&v, 1, sizeof(v), f) != sizeof(v)) { fclose(f); return 1; }
  fclose(f);
  return v ? v : 1;
}
static void otp_write(uint32_t v){
  FILE* f = fopen("out/otp_counter.bin","wb");
  if (!f) return;
  (void)fwrite(&v, 1, sizeof(v), f);
  fclose(f);
}

// --- Verify one slot (header + payload). Returns 1 on PASS, 0 on FAIL. ---
static int verify_slot(const char* hdr_path, const char* fw_path) {
  uint8_t *hdr=NULL, *fw=NULL; size_t hdr_len=0, fw_len=0;

  printf(C_YEL "[*] Verifying slot: %s, %s\n" C_RST, hdr_path, fw_path);

  if (load_file(hdr_path, &hdr, &hdr_len) || load_file(fw_path, &fw, &fw_len)) {
    printf(C_RED "[-] Failed to load header/payload\n" C_RST); goto fail;
  }
  if (hdr_len < HDR_SIZE) { printf(C_RED "[-] Header too small\n" C_RST); goto fail; }

  fw_header_t h; memcpy(&h, hdr, sizeof(fw_header_t));

  // Basic structural checks
  if (h.magic != HDR_MAGIC || h.header_size != HDR_SIZE) {
    printf(C_RED "[-] Bad magic or header_size\n" C_RST); goto fail;
  }
  if (h.fw_size != fw_len) {
    printf(C_RED "[-] Size mismatch: header=%u, file=%zu\n" C_RST, h.fw_size, fw_len); goto fail;
  }
  if ((size_t)HDR_BLOB_OFFSET + (size_t)h.pk_len + (size_t)h.sig_len > (size_t)HDR_SIZE) {
    printf(C_RED "[-] Header blob overflow\n" C_RST); goto fail;
  }

  // NEW: strict algorithm size checks (bind to Dilithium‑2)
  if (h.pk_len != D2_PK_LEN || h.sig_len != D2_SIG_LEN) {
    printf(C_RED "[-] Bad key/signature lengths (pk=%u, sig=%u)\n" C_RST, h.pk_len, h.sig_len);
    goto fail;
  }

  const uint8_t* blob = hdr + HDR_BLOB_OFFSET;
  const uint8_t* pk   = blob;
  const uint8_t* sig  = blob + h.pk_len;

  // PK-hash binding (OTP contains SHA-256 of allowed PK)
  uint8_t pk_hash[32];
  if (sha256(pk, h.pk_len, pk_hash) != 0) { printf(C_RED "[-] pk hash calc failed\n" C_RST); goto fail; }
  if (memcmp(pk_hash, OTP_PK_HASH, 32) != 0) { printf(C_RED "[-] PK mismatch vs OTP\n" C_RST); goto fail; }

  // Firmware digest
  uint8_t digest[64];
  if (fw_digest(fw, fw_len, digest) != 0) { printf(C_RED "[-] Digest failed\n" C_RST); goto fail; }

  // Dilithium verify
  if (dilithium_verify_digest(digest, sizeof(digest), sig, h.sig_len, pk, h.pk_len) != 0) {
    printf(C_RED "[-] Signature verify FAIL\n" C_RST); goto fail;
  }

  // Anti-rollback (monotonic)
  uint32_t vmin = otp_read();
  if (h.version < vmin) {
    printf(C_RED "[-] Rollback: version=%u < %u\n" C_RST, h.version, vmin); goto fail;
  }
  if (h.version > vmin) {
    otp_write(h.version);
    printf(C_GRN "[+] OTP counter updated to %u\n" C_RST, h.version);
  }

  printf(C_GRN "[+] VERIFY PASS — jumping to firmware (%s)\n" C_RST, fw_path);
  free(hdr); free(fw);
  return 1;

fail:
  if (hdr) free(hdr);
  if (fw)  free(fw);
  return 0;
}

// --- Main: <hdr_a> <fw_a> <hdr_b> <fw_b> ---
int main(int argc, char** argv) {
  if (argc != 5) {
    fprintf(stderr, "Usage: %s <hdr_a> <fw_a> <hdr_b> <fw_b>\n", argv[0]);
    return 1;
  }
  if (verify_slot(argv[1], argv[2])) return 0;
  printf(C_YEL "[*] Slot A failed, trying Slot B...\n" C_RST);
  if (verify_slot(argv[3], argv[4])) return 0;
  printf(C_RED "[X] Both slots failed verification. System halt.\n" C_RST);
  return 1;
}
