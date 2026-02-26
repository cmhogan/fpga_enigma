# Copyright (c) 2026, Chad Hogan
# All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# Makefile — FPGA Enigma I build and test automation
#
# Targets:
#   make test    — run all regression testbenches (default)
#   make lint    — Verilator lint on synthesizable RTL
#   make synth   — synthesize via apio
#   make upload  — program FPGA via apio
#   make clean   — remove build artifacts

RTL_DIR  := rtl
TB_DIR   := tb
BUILD    := build
RTL_SRC  := $(wildcard $(RTL_DIR)/*.v)

# Regression testbenches (basenames without .v)
TESTBENCHES := enigma_tb error_handling_tb rotor_coverage_tb timeout_tb plugboard_tb stepper_tb plugboard_tb_unit config_manager_tb uart_tb

.PHONY: all test clean lint synth upload coverage

all: test

# ---- Simulation -----------------------------------------------------------

test: $(addprefix test_,$(TESTBENCHES))
	@echo ""
	@echo "=== All regression testbenches passed ==="

test_%: $(TB_DIR)/%.v $(RTL_SRC) | $(BUILD)
	@echo ""
	@echo "--- Running $* ---"
	@iverilog -DSIMULATION -I$(RTL_DIR) -o $(BUILD)/$*.vvp $< $(RTL_SRC) \
		&& vvp $(BUILD)/$*.vvp | tee $(BUILD)/$*.log \
		&& if grep -q '[1-9][0-9]* failed' $(BUILD)/$*.log; then \
			echo "FAIL: $*"; exit 1; \
		fi

# ---- Coverage -------------------------------------------------------------

coverage: $(addprefix cov_,$(TESTBENCHES))
	@echo ""
	@echo "=== Generating coverage summary ==="
	@bash scripts/coverage_summary.sh

cov_%: $(TB_DIR)/%.v $(RTL_SRC) | $(BUILD)
	@echo "--- Coverage run: $* ---"
	@iverilog -DSIMULATION -DVCD_DUMP -I$(RTL_DIR) -o $(BUILD)/$*.vvp $< $(RTL_SRC) \
		&& vvp $(BUILD)/$*.vvp > $(BUILD)/$*_cov.log 2>&1

# ---- Lint -----------------------------------------------------------------

lint: | $(BUILD)
	verilator --lint-only -Wall -I$(RTL_DIR) $(RTL_SRC) --top-module enigma_top 2>&1 \
		| tee $(BUILD)/lint.log

# ---- Synthesis check ------------------------------------------------------

synth-check: | $(BUILD)
	yosys -p "read_verilog -I rtl rtl/*.v; synth_ice40 -top enigma_top" \
		-l $(BUILD)/synth-check.log

# ---- APIO passthrough -----------------------------------------------------

synth:
	apio build

upload:
	apio upload

# ---- Housekeeping ---------------------------------------------------------

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)/*.vvp $(BUILD)/*.vcd $(BUILD)/*.log
	-apio clean 2>/dev/null
