# Copyright (c) 2026, Chad Hogan
# All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
#
# upload.tcl — Parameterized Vivado upload script for Artix-7 boards
#
# Usage (from repo root, board must be connected via USB):
#   vivado -mode batch -source tcl/upload.tcl -tclargs <board>
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
    arty  { set bit_file build/enigma_arty_a7.bit }
    nexys { set bit_file build/enigma_nexys_a7.bit }
    default {
        puts "ERROR: Unknown board '$board'. Supported: arty, nexys"
        exit 1
    }
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device

close_hw_target
disconnect_hw_server
close_hw_manager

exit
