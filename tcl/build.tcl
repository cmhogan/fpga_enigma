# Copyright (c) 2026, Chad Hogan
# All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
#
# build.tcl — Parameterized Vivado batch build script for Artix-7 boards
# Part:  xc7a100tcsg324-1  (shared by Arty A7-100T and Nexys A7-100T)
#
# Usage (from repo root):
#   vivado -mode batch -source tcl/build.tcl -tclargs <board>
#
# Supported boards:
#   arty   — Digilent Arty A7-100T
#   nexys  — Digilent Nexys A7-100T

if {$argc != 1} {
    puts "ERROR: Expected one argument: board name (arty or nexys)"
    exit 1
}

set board [lindex $argv 0]

switch $board {
    arty {
        set top_module enigma_top_arty
        set xdc_file   constraints/arty_a7_100t.xdc
        set bit_file   build/enigma_arty_a7.bit
        set timing_rpt build/arty_a7_timing.rpt
        set util_rpt   build/arty_a7_utilization.rpt
    }
    nexys {
        set top_module enigma_top_nexys
        set xdc_file   constraints/nexys_a7_100t.xdc
        set bit_file   build/enigma_nexys_a7.bit
        set timing_rpt build/nexys_a7_timing.rpt
        set util_rpt   build/nexys_a7_utilization.rpt
    }
    default {
        puts "ERROR: Unknown board '$board'. Supported: arty, nexys"
        exit 1
    }
}

set part xc7a100tcsg324-1

create_project -in_memory -part $part

# Read all RTL sources
read_verilog [glob rtl/*.v rtl/*.vh]
set_property file_type {Verilog Header} [get_files rtl/enigma_common.vh]

# Read constraints
read_xdc $xdc_file

# Synthesis
synth_design -top $top_module -part $part

# Implementation
opt_design
place_design
route_design

# Reports
report_timing_summary -file $timing_rpt
report_utilization    -file $util_rpt

# Bitstream
write_bitstream -force $bit_file

exit
