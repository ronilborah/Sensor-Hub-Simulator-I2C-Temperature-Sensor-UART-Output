## ===== CLOCK =====
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.0 [get_ports clk]

## ===== RESET =====
set_property PACKAGE_PIN P16 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

## ===== TRIGGER =====
set_property PACKAGE_PIN N15 [get_ports trigger]
set_property IOSTANDARD LVCMOS33 [get_ports trigger]

## ===== UART TX (JE1 on Pmod header) =====
set_property PACKAGE_PIN V12 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## ===== I2C LINES (JA Pmod header) =====
set_property PACKAGE_PIN Y11 [get_ports scl]
set_property IOSTANDARD LVCMOS33 [get_ports scl]
set_property PULLUP TRUE [get_ports scl]

set_property PACKAGE_PIN AA11 [get_ports sda]
set_property IOSTANDARD LVCMOS33 [get_ports sda]
set_property PULLUP TRUE [get_ports sda]

## ===== CONFIG =====
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]