# sensor_hub.xdc - Template constraints for ZedBoard (XC7Z020)
# Replace <...> placeholders with the actual PACKAGE_PIN names for your board.
# Consult the ZedBoard user guide / board files in Vivado to find correct PACKAGE_PIN values.

# Top-level ports in `sensor_hub_top`:
#   clk    : system clock input
#   rst    : active-high reset (pushbutton)
#   trigger: external trigger (pushbutton)
#   uart_tx: UART TX output
#   scl    : I2C SCL
#   sda    : I2C SDA (bidirectional, open-drain)

## Clock
set_property PACKAGE_PIN L16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 [get_ports clk]

## Reset button
set_property PACKAGE_PIN J19 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property PULLUP TRUE [get_ports rst]

## Trigger switch/button
set_property PACKAGE_PIN K18 [get_ports trigger]
set_property IOSTANDARD LVCMOS33 [get_ports trigger]
set_property PULLUP TRUE [get_ports trigger]

## UART TX
set_property PACKAGE_PIN W18 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## I2C
set_property PACKAGE_PIN P15 [get_ports scl]
set_property IOSTANDARD LVCMOS33 [get_ports scl]
set_property PULLUP TRUE [get_ports scl]

set_property PACKAGE_PIN N15 [get_ports sda]
set_property IOSTANDARD LVCMOS33 [get_ports sda]
set_property PULLUP TRUE [get_ports sda]

# --- Timing and other guidance ---
# - Replace <CLK_PIN>, <RST_PIN>, <TRIG_PIN>, <UART_TX_PIN>, <SCL_PIN>, <SDA_PIN>
#   with the PACKAGE_PIN names from the ZedBoard schematics or the Vivado board file.
# - For ZedBoard, common choices are PMOD or Arduino header pins; check the board user guide.
# - If the I2C bus connects to external sensors/modules, prefer 4.7k pull-ups to 3.3V on SCL/SDA.
# - If your clock frequency differs, update the `create_clock -period` value accordingly.
# - After editing this XDC, add it to your Vivado project (Project Settings -> Add Sources -> Add or Create Constraints)
#   then run Synthesis/Implementation. If Vivado reports pin/mapping errors, replace the placeholders with valid pins.

# End of sensor_hub.xdc
