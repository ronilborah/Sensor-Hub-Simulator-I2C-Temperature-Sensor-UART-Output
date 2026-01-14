# Mini Project 1

## Sensor Hub Simulator (I²C Temperature Sensor + UART Output)

**Target Board:** Zynq ZedBoard (xc7z020)  
**Language:** Verilog (PL-only, no PS)  
**Output:** Serial terminal displays `Temp = 25`

---

# 🚨 QUICK START – FOLLOW THESE STEPS IN ORDER (DO NOT SKIP)

1. Open **Vivado**
2. Create **RTL Project**
3. Select **ZedBoard (xc7z020clg484-1)**
4. Add **ONE source file**: `sensor_hub_top.v`
5. Set **Top Module = sensor_hub_top**
6. Add **XDC constraints** (clock, reset, UART, I²C)
7. Connect **external 4.7kΩ pull-ups** on SDA & SCL
8. Generate **bitstream**
9. Program **ZedBoard**
10. Open **serial terminal @ 9600 baud**
11. Press **RESET**
12. Press **TRIGGER**
13. Observe output: Temp = 25
    If any step fails → go to **Debug Checklist** at the bottom.

---

# 1️⃣ PROJECT OVERVIEW

This project demonstrates how an FPGA can replace a microcontroller to:

- Act as an **I²C Master**
- Read data from an **I²C temperature sensor**
- Convert numeric data to **ASCII**
- Transmit results using **UART**
- Display data on a **PC terminal**

The temperature sensor is implemented as a **dummy I²C slave** inside the FPGA that always returns **25°C**.

---

# 2️⃣ FUNCTIONAL FLOWTrigger Button

↓
I²C Master (FPGA)
↓
Dummy I²C Slave (25°C)
↓
Temperature Byte
↓
ASCII Conversion
↓
UART TX
↓
USB-UART (ZedBoard)
↓
PC Terminal---

# 3️⃣ HARDWARE REQUIREMENTS

## Board

- Zynq ZedBoard
- USB cable (JTAG)
- USB cable (UART)

## External Components (MANDATORY)

- 2 × **4.7 kΩ resistors**
  - SDA → 3.3V
  - SCL → 3.3V

⚠️ **Without pull-ups, I²C WILL NOT WORK**

---

# 4️⃣ SIGNAL MAPPING (PL ONLY)

| Signal    | Direction | Description                      |
| --------- | --------- | -------------------------------- |
| `clk`     | Input     | 100 MHz onboard clock            |
| `rst`     | Input     | Push button reset                |
| `trigger` | Input     | Push button to start transaction |
| `scl`     | Output    | I²C clock                        |
| `sda`     | Inout     | I²C data (open-drain)            |
| `uart_tx` | Output    | UART transmit to PC              |

---

# 5️⃣ PHYSICAL WIRING (VERY IMPORTANT)

## I²C (PMOD Header – Example: JA)

| I²C Signal | ZedBoard Pin |
| ---------- | ------------ |
| SCL        | JA2          |
| SDA        | JA1          |

### External Pull-ups

- 4.7 kΩ from **SDA → 3.3V**
- 4.7 kΩ from **SCL → 3.3V**

---

## UART

- Use **onboard USB-UART**
- Only **TX** is required
- No RX connection needed

---

# 6️⃣ VIVADO PROJECT SETUP

## Step 1: Create Project

- Open Vivado
- Create **RTL Project**
- Do **NOT** add sources yet

## Step 2: Select Board

- Board: **ZedBoard**
- Part: **xc7z020clg484-1**

## Step 3: Add Source

- Add **single Verilog file**sensor_hub_top.v## Step 4: Set Top Module## Step 4: Set Top Modulesensor_hub_top

---

# 7️⃣ XDC CONSTRAINTS (CRITICAL)

Create `zedboard_sensor_hub.xdc`

## Clock (100 MHz)

```xdc
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.0 [get_ports clk]
set_property PACKAGE_PIN P16 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]
set_property PACKAGE_PIN N15 [get_ports trigger]
set_property IOSTANDARD LVCMOS33 [get_ports trigger]
set_property PACKAGE_PIN D4 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN E15 [get_ports scl]
set_property IOSTANDARD LVCMOS33 [get_ports scl]

set_property PACKAGE_PIN E16 [get_ports sda]
set_property IOSTANDARD LVCMOS33 [get_ports sda]
⚠️ Do NOT enable internal pull-ups for SDA/SCL

⸻

8️⃣ BUILD & PROGRAM FPGA
	1.	Run Synthesis
	2.	Run Implementation
	3.	Generate Bitstream
	4.	Open Hardware Manager
	5.	Program device

Wait until programming completes successfully.

⸻

9️⃣ PC TERMINAL SETUP

Use any serial terminal:
	•	PuTTY
	•	TeraTerm
	•	minicom
	•	screen

    settings Parameter
Value
Baud rate
9600
Data bits
8
Parity
None
Stop bits
1
Flow control
None
🔟 RUNNING THE DEMO
	1.	Power ON ZedBoard
	2.	Open serial terminal
	3.	Press RESET
	4.	Press TRIGGER

Expected OutputTemp = 25(One line per trigger press)
1️⃣1️⃣ DEBUG CHECKLIST

❌ Nothing prints
	•	Wrong COM port
	•	UART baud not 9600
	•	uart_tx pin incorrect
	•	Board not programmed

❌ Garbage characters
	•	Clock constraint wrong
	•	Wrong baud divider
	•	Wrong clock frequency assumption

❌ I²C stuck / no output
	•	Missing pull-up resistors
	•	SDA/SCL swapped
	•	Wrong PMOD pins

❌ Prints only once
	•	Trigger button not debounced (expected)
	•	Press trigger again

⸻

1️⃣2️⃣ DESIGN NOTES (FOR VIVA)
	•	I²C is open-drain, never driven high
	•	Dummy slave always returns 25°C
	•	ACK from master after data is ignored (dummy behavior)
	•	No clock stretching or multi-byte reads (intentional simplification)
	•	Entire design runs in PL only

⸻

1️⃣3️⃣ EXPECTED QUESTIONS & ANSWERS

Q: Is this full I²C compliant?
A: Essential phases are implemented. Advanced features are omitted for simplicity.

Q: Why external pull-ups?
A: I²C requires pull-ups because devices only pull the line low.

Q: Why no ARM processor?
A: Demonstrates pure FPGA-based sensor interfacing.

⸻

✅ FINAL CHECK BEFORE LEAVING LAB
	•	Bitstream programmed
	•	Pull-ups connected
	•	Terminal shows correct baud
	•	Output matches expected
	•	Screenshots taken (for report)

⸻

🎯 FINAL RESULT

The FPGA successfully:
	•	Reads temperature via I²C
	•	Converts to ASCII
	•	Transmits over UART
	•	Displays data on PC terminal

Mini Project Complete.
```
