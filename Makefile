# Makefile (repo root)

CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
PREFIX ?= $(HOME)/.local
OQS_INC ?= $(PREFIX)/include
OQS_LIB ?= $(PREFIX)/lib
RPATH ?= $(OQS_LIB)

ROM := rom_mock
OTP_HDR := rom/otp_pk.h

.PHONY: all clean lab_flow demo demo-clean report test_ab \
        demo_baseline demo_ab_counter demo_rollback_only \
        demo_rollback_fail demo_bump_to_2 footprint all-demos \
        verify-matrix demo-suite

all: $(ROM) gen_keys_c sign_fw_c test_matrix

$(OTP_HDR): out/pub.key tools/gen_otp_header.sh
	tools/gen_otp_header.sh out/pub.key

$(ROM): $(OTP_HDR) rom/boot_rom.c sw/verify_lib.c rom/image_format.h
	@echo "=== [1/4] Building ROM mock (secure boot simulator) ==="
	$(CC) $(CFLAGS) -Irom -I$(OQS_INC) -L$(OQS_LIB) -o $@ \
	    rom/boot_rom.c sw/verify_lib.c \
	    -loqs -lcrypto -lpthread -Wl,-rpath,$(RPATH)

gen_keys_c: tools/gen_keys_c.c
	@echo "=== [2/4] Building Key Generator Tool ==="
	$(CC) $(CFLAGS) -I$(OQS_INC) -L$(OQS_LIB) -o tools/gen_keys_c \
	    tools/gen_keys_c.c \
	    -loqs -lcrypto -lpthread -Wl,-rpath,$(RPATH)

sign_fw_c: tools/sign_fw_c.c
	@echo "=== [3/4] Building Firmware Signing Tool ==="
	$(CC) $(CFLAGS) -Irom -I$(OQS_INC) -L$(OQS_LIB) -o tools/sign_fw_c \
	    tools/sign_fw_c.c \
	    -loqs -lcrypto -lpthread -Wl,-rpath,$(RPATH)

test_matrix: tools/test_matrix.sh
	@echo "=== [4/4] Making test matrix script executable ==="
	chmod +x tools/test_matrix.sh

lab_flow: all
	@echo ">>> [Step 1] Creating output directory..."
	mkdir -p out
	@echo ">>> [Step 2] Generating 4 KiB firmware payload..."
	dd if=/dev/urandom of=out/firmware.payload bs=4096 count=1
	@echo ">>> [Step 3] Generating Dilithium key pair..."
	./tools/gen_keys_c out/pub.key out/sec.key
	@echo ">>> [Step 4] Generating OTP header from public key..."
	tools/gen_otp_header.sh out/pub.key
	@echo ">>> [Step 5] Rebuilding ROM mock with new OTP..."
	$(MAKE) $(ROM)
	@echo ">>> [Step 6] Signing firmware (version 1)..."
	./tools/sign_fw_c out/firmware.payload out/pub.key out/sec.key 1 out/firmware.header
	@echo ">>> [Step 7] Running secure boot verification..."
	./rom_mock out/firmware.header out/firmware.payload out/firmware.header out/firmware.payload
	@echo "=== LAB COMPLETE ==="

test_ab:
	@echo "=== [A/B Slot Simulation] ==="
	@./tools/test_ab_slots.sh

# --- Demos ---
demo_baseline: ; @./tools/demo_baseline.sh
demo_ab_counter: ; @./tools/demo_ab_counter.sh
demo_rollback_only: ; @./tools/demo_rollback_only.sh
demo_rollback_fail: ; @./tools/demo_rollback_fail.sh
demo_bump_to_2: ; @./tools/demo_bump_to_2.sh
footprint: ; @./tools/measure_footprint.sh
all-demos: ; @./tools/run_all_demos.sh

# --- Verification matrix ---
verify-matrix: ; @./tools/verify_matrix.sh
demo-suite: ; @./tools/secure_boot_demo_suite.sh

demo: ; ./demo.sh
demo-clean: ; rm -rf build sim/obj_dir sw/golden/signer

clean:
	rm -f rom_mock tools/gen_keys_c tools/sign_fw_c rom/otp_pk.h

report: all
	@echo ">>> Running PASS and FAIL flows and generating HTML diff…"
	@chmod +x tools/run_matrix_and_log.sh tools/run_all_pass_and_log.sh tools/run_and_compare.sh
	@./tools/run_and_compare.sh
	@echo ">>> Report at: out/pass_vs_fail_diff.html"
	@command -v xdg-open >/dev/null 2>&1 && xdg-open out/pass_vs_fail_diff.html || true

.PHONY: golden
golden:
	./tools/golden.sh

.PHONY: sweep sign-file
sweep:
	./tools/size_sweep.sh
sign-file:
	./tools/sign_file.sh $(file) $(ver)
