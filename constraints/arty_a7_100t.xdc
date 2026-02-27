# BSD 3-Clause License
#
# Copyright (c) 2026, Chad Hogan
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# Vivado XDC Constraints — Arty A7-100T (xc7a100tcsg324-1)
# Top-level module: enigma_top_arty

## Clock — 100 MHz XTAL oscillator
set_property PACKAGE_PIN E3 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk_100mhz]

## Reset — BTN0 (active-high button); polarity inversion handled in rtl/enigma_top_arty.v
set_property PACKAGE_PIN C2 [get_ports ext_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports ext_rst_n]

## UART — USB-UART bridge (FTDI)
# uart_rx: FPGA receives from host (FTDI TXD → FPGA RXD)
set_property PACKAGE_PIN A9 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
# uart_tx: FPGA sends to host (FPGA TXD → FTDI RXD)
set_property PACKAGE_PIN D10 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## LEDs
# led_d1 — Heartbeat (LD0, green)
set_property PACKAGE_PIN H5 [get_ports led_d1]
set_property IOSTANDARD LVCMOS33 [get_ports led_d1]
# led_d2 — RX activity (LD1, green)
set_property PACKAGE_PIN J5 [get_ports led_d2]
set_property IOSTANDARD LVCMOS33 [get_ports led_d2]
# led_d3 — TX activity (LD2, green)
set_property PACKAGE_PIN T9 [get_ports led_d3]
set_property IOSTANDARD LVCMOS33 [get_ports led_d3]
# led_d4 — Command mode (LD3, green)
set_property PACKAGE_PIN T10 [get_ports led_d4]
set_property IOSTANDARD LVCMOS33 [get_ports led_d4]
# led_d5 — Error indicator (LD4_R, red channel of RGB LED)
set_property PACKAGE_PIN G6 [get_ports led_d5]
set_property IOSTANDARD LVCMOS33 [get_ports led_d5]
