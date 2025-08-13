CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
OQS_INC ?= /usr/local/include
OQS_LIB ?= /usr/local/lib

.PHONY: all clean lab_flow

all: rom_mock gen_keys_c sign_fw_c test_matrix

rom_mock: rom/boot_rom.c sw/verify_lib.c rom/image_format.h
	@echo "=== [1/4] Building ROM mock (secure boot simulator) ==="
	$(CC) $(CFLAGS) -Irom -I$(OQS_INC) -L$(OQS_LIB) -o $@ rom/boot_rom.c sw/verify_lib.c $(LDFLAGS) -loqs -lcrypto -Wl,-rpath,/usr/local/lib
	@sleep 20

gen_keys_c: tools/gen_keys_c.c
	@echo "=== [2/4] Building Key Generator Tool ==="
	$(CC) $(CFLAGS) -I$(OQS_INC) -L$(OQS_LIB) -o tools/gen_keys_c tools/gen_keys_c.c -loqs -Wl,-rpath,/usr/local/lib
	@sleep 20

sign_fw_c: tools/sign_fw_c.c
	@echo "=== [3/4] Building Firmware Signing Tool ==="
	$(CC) $(CFLAGS) -Irom -I$(OQS_INC) -L$(OQS_LIB) -o tools/sign_fw_c tools/sign_fw_c.c -loqs -lcrypto -Wl,-rpath,/usr/local/lib
	@sleep 20

test_matrix: tools/test_matrix.sh
	@echo "=== [4/4] Making test matrix script executable ==="
	chmod +x tools/test_matrix.sh
	@sleep 20

lab_flow: all
	@echo ">>> [Step 1] Creating output directory..."
	mkdir -p out
	sleep 20

	@echo ">>> [Step 2] Generating dummy firmware payload..."
	dd if=/dev/urandom of=out/firmware.payload bs=1k count=4
	sleep 20

	@echo ">>> [Step 3] Generating Dilithium key pair..."
	./tools/gen_keys_c out/pubkey.bin out/seckey.bin
	sleep 20

	@echo ">>> [Step 4] Signing firmware..."
	./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
	sleep 20

	@echo ">>> [Step 5] Running secure boot verification..."
	./rom_mock out/firmware.header out/firmware.payload
	sleep 20

	@echo ">>> [Step 6] Running tamper and rollback tests..."
	./tools/test_matrix.sh
	sleep 20

	@echo "=== LAB COMPLETE ==="

test_ab:
	@echo "=== [A/B Slot Simulation] ==="
	@./tools/test_ab_slots.sh


# --- Demos ---
demo_baseline:
	@./tools/demo_baseline.sh

demo_ab_counter:
	@./tools/demo_ab_counter.sh

demo_rollback_only:
	@./tools/demo_rollback_only.sh

demo_rollback_fail:
	@./tools/demo_rollback_fail.sh

demo_bump_to_2:
	@./tools/demo_bump_to_2.sh

footprint:
	@./tools/measure_footprint.sh

all-demos:
	@./tools/run_all_demos.sh

# --- Verification matrix (see tools/verify_matrix.sh) ---
verify-matrix:
	@./tools/verify_matrix.sh



clean:
	rm -f rom_mock tools/gen_keys_c tools/sign_fw_c

# --- Generate PASS vs FAIL report and open it ---
.PHONY: report
report: all
	@echo ">>> Running PASS and FAIL flows and generating HTML diff…"
	@chmod +x tools/run_matrix_and_log.sh tools/run_all_pass_and_log.sh tools/run_and_compare.sh
	@./tools/run_and_compare.sh
	@echo ">>> Report at: out/pass_vs_fail_diff.html"
	@command -v xdg-open >/dev/null 2>&1 && xdg-open out/pass_vs_fail_diff.html || true
