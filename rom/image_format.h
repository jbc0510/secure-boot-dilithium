#pragma once
#include <stdint.h>

#define HDR_MAGIC 0x44494C49u  // 'DILI'
#define HDR_SIZE  4096u

typedef struct __attribute__((packed)) {
  uint32_t magic;
  uint32_t header_size;
  uint32_t version;
  uint32_t fw_size;
  uint32_t pk_len;
  uint32_t sig_len;
} fw_header_t;

#define HDR_BLOB_OFFSET 0x18
