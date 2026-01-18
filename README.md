# Sensor Hub Simulator — I²C Temperature Sensor + UART Output

This repository implements a Verilog-based sensor-hub simulator where an FPGA reads temperature data from an I²C temperature sensor (simulated by a dummy slave module), converts the value to ASCII, and transmits it over UART to a PC terminal.

**Expected Output:** `Temp = 25`

---

## Repository Contents

### Core Modules

- **`i2c_slave_dummy.v`** — I²C slave device that simulates a temperature sensor, responds to address `0x48` and returns a fixed temperature value (25°C / 0x19 hex)
- **`tb_i2c_slave_dummy.v`** — Testbench for I²C slave module with START/STOP conditions and byte transfer validation
- **`uart_tx.v`** — UART transmitter with baud rate generator, FSM-based transmission control, and shift register
- **`tb_uart_tx.v`** — Testbench for UART transmitter module
- **`ascii_encoder.v`** — Converts binary temperature value to ASCII digit characters (tens and ones place)
- **`buildstring.v`** — Builds the complete ASCII string "Temp = 25\r\n" for UART transmission

---

## System Architecture and Data Flow

### Overall Workflow

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌──────────┐
│   I²C       │ read │   ASCII      │ feed │ buildstring │ send │  UART    │
│   Slave     ├─────→│   Encoder    ├─────→│   Module    ├─────→│  TX      │──→ PC
│ (Sensor)    │ 0x19 │              │ chars│             │ bits │          │
└─────────────┘      └──────────────┘      └─────────────┘      └──────────┘
     ↑                                                                  ↓
     │                                                                  │
   SCL/SDA                                                          tx (serial)
```

### Step-by-Step Data Flow

1. **I²C Read Transaction** (`i2c_slave_dummy.v`)
   - Master sends START condition
   - Master transmits slave address (0x48) + Read bit
   - Slave acknowledges (ACK)
   - Slave transmits temperature data byte (0x19 = 25 decimal)
   - Master acknowledges
   - Master sends STOP condition

2. **Binary to ASCII Conversion** (`ascii_encoder.v`)
   - Input: 8-bit binary value (25 = 0x19)
   - Tens digit: 25 ÷ 10 = 2 → ASCII '2' (0x32)
   - Ones digit: 25 % 10 = 5 → ASCII '5' (0x35)
   - Output: Two ASCII characters

3. **String Building** (`buildstring.v`)
   - Constructs complete message: "Temp = 25\r\n"
   - Character sequence: 'T', 'e', 'm', 'p', ' ', '=', ' ', '2', '5', '\r', '\n'
   - Selects character based on index input

4. **UART Transmission** (`uart_tx.v`)
   - Each ASCII character is transmitted serially
   - Frame format: [START(0)] + [8 data bits, LSB first] + [STOP(1)]
   - Baud rate controlled by clock divider
   - Example: 'T' (0x54) → bits: 0 0 0 1 0 1 0 1 0 1

---

## Detailed Code Explanations

### 1. I²C Slave Module (`i2c_slave_dummy.v`)

**Purpose:** Simulates an I²C temperature sensor that responds to read requests with a fixed temperature value.

**Key Components:**

```verilog
// FSM States
IDLE      → Waiting for START condition
ADDR      → Receiving 7-bit address + R/W bit
ACK_ADDR  → Acknowledging address match
SEND_DATA → Transmitting temperature byte
WAIT_ACK  → Waiting for master's ACK
```

**Critical Implementation Details:**

- **START/STOP Detection (Asynchronous):**

  ```verilog
  assign start_cond = (sda_prev == 1'b1) && (sda_in == 1'b0) && (scl == 1'b1);
  assign stop_cond  = (sda_prev == 1'b0) && (sda_in == 1'b1) && (scl == 1'b1);
  ```

  - START: SDA falls while SCL is HIGH
  - STOP: SDA rises while SCL is HIGH
  - These are detected independently of SCL edges

- **Open-Drain Signaling:**
  - `sda_oe` (output enable) controls when slave pulls SDA low
  - When `sda_oe = 1`, slave pulls SDA to 0 (ACK or data bit = 0)
  - When `sda_oe = 0`, SDA is released (high-impedance, pulled high by external resistor)

- **Address Matching:**
  - Slave address: 0x48 (7 bits)
  - Compares received address with `SLAVE_ADDR`
  - Only responds if address matches

- **Data Transmission:**
  - Temperature data: 25°C = 0x19 (hexadecimal) = 0001 1001 (binary)
  - Transmitted MSB first on falling SCL edge
  - Uses shift register to serialize the byte

**Timing Diagram:**

```
SCL:  ──┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌───
        │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
SDA:  ──┘ │0│1│0│0│1│0│0│0│ │ ACK │ DATA... │ STOP
START    └─┴─┴─┴─┴─┴─┴─┴─┴─┘       └─────────┘
         Address (0x48) + R
```

**I²C Slave Waveform (GTKWave):**

![I²C Slave Waveform](screenshots/i2c_slave_waveform.jpeg)

_Waveform showing complete I²C transaction: START condition, address byte (0x48), ACK, data byte (0x19), and STOP condition_

---

### 2. UART Transmitter Module (`uart_tx.v`)

**Purpose:** Serializes 8-bit data bytes and transmits them over a single wire at a specified baud rate.

**Key Components:**

```verilog
// FSM States
IDLE  → Waiting for tx_start signal, tx line held HIGH
START → Transmit start bit (0)
DATA  → Shift out 8 data bits (LSB first)
STOP  → Transmit stop bit (1)
```

**Baud Rate Generation:**

```verilog
BAUD_DIV = CLK_FREQ / BAUD_RATE
// Example: 1MHz / 9600 = 104 clock cycles per bit
```

**Transmission Process:**

1. Wait for `tx_start` signal (IDLE state)
2. Send start bit (logic 0) for one baud period
3. Send 8 data bits, LSB first, each for one baud period
4. Send stop bit (logic 1) for one baud period
5. Return to IDLE, set `tx_busy = 0`

**Frame Format Example:**

```
Transmitting 'T' (ASCII 0x54 = 0101 0100)

tx: ──┐     ┌───┐   ┐   ┌───┐   ┌───────┐
      │     │   │   │   │   │   │       │
      └─────┘   └───┘   └───┘   └───────┘
      IDLE START 0 0 1 0 1 0 1 0  STOP IDLE
             │←──── 8 bits ────→│
           (LSB)            (MSB)
```

**Critical Timing:**

- Each bit period = `BAUD_DIV` clock cycles
- `baud_tick` pulses once per bit period
- State transitions occur only on `baud_tick`

---

### 3. ASCII Encoder Module (`ascii_encoder.v`)

**Purpose:** Converts a binary temperature value (0-99) into two ASCII digit characters.

**Algorithm:**

```verilog
Input: value = 25 (decimal)

tens = 25 / 10 = 2
ones = 25 % 10 = 5

tens_ascii = '0' + tens = 48 + 2 = 50 = '2'
ones_ascii = '0' + ones = 48 + 5 = 53 = '5'

Output: tens_ascii = 0x32 ('2'), ones_ascii = 0x35 ('5')
```

**ASCII Table Reference:**

- '0' = 48 (0x30)
- '1' = 49 (0x31)
- ...
- '9' = 57 (0x39)

**Combinational Logic:**

- Pure combinational module (no clock, no state)
- Division and modulo operations synthesized as logic gates
- Output updates instantly when input changes

**ASCII Encoder Output:**

![ASCII Encoder](screenshots/ascii%20ss.png)

_ASCII encoder converting binary temperature value to ASCII characters for display_

---

### 4. Build String Module (`buildstring.v`)

**Purpose:** Creates a complete ASCII message string with temperature value embedded.

**Character Sequence:**

```
Index:  0    1    2    3    4    5    6    7    8    9     10
Char:  'T'  'e'  'm'  'p'  ' '  '='  ' '  '2'  '5'  '\r'  '\n'
Hex:   54   65   6D   70   20   3D   20   32   35   0D    0A
```

**Module Operation:**

1. Takes an index input (0-10)
2. Uses case statement to select corresponding character
3. Positions 7 and 8 are dynamically filled with temperature digits
4. Returns the selected character as 8-bit output

**Usage Example:**

```verilog
// To send full string via UART:
for (i = 0; i < 11; i++) {
    buildstring bs (.value(25), .index(i), .char_out(current_char));
    uart_tx     tx (.tx_data(current_char), .tx_start(1), ...);
    wait_for_uart_done();
}
```

---

### 5. Testbenches

#### I²C Testbench (`tb_i2c_slave_dummy.v`)

**Key Features:**

- Generates SCL clock signal
- Models open-drain SDA bus with tri-state logic
- Implements I²C master tasks: `i2c_start()`, `i2c_stop()`, `i2c_write_byte()`, `i2c_read_byte()`
- Simulates complete read transaction
- Generates VCD waveform file for analysis

**Test Sequence:**

1. Reset slave
2. Generate START condition
3. Send slave address (0x48) + READ bit
4. Check for ACK from slave
5. Read data byte (expect 0x19)
6. Send NACK (master not requesting more data)
7. Generate STOP condition
8. Verify received data matches expected value

#### UART Testbench (`tb_uart_tx.v`)

**Key Features:**

- Generates system clock
- Sends test bytes to UART module
- Monitors `tx` output and `tx_busy` flag
- Validates timing and bit patterns
- Generates VCD for waveform inspection

**Test Sequence:**

1. Reset UART module
2. Load test data byte (e.g., 0x41 = 'A')
3. Assert `tx_start` signal
4. Wait for transmission to complete (`tx_busy` goes low)
5. Verify start bit, 8 data bits (LSB first), and stop bit
6. Repeat with different test values

---

## Quick Start — Simulation with Icarus Verilog

### 1. Install Tools (macOS)

```bash
brew install icarus-verilog gtkwave
```

### 2. Run I²C Slave Testbench

```bash
iverilog -o i2c_tb.vvp i2c_slave_dummy.v tb_i2c_slave_dummy.v
vvp i2c_tb.vvp
gtkwave i2c_slave_dummy.vcd
```

**Expected Waveform:** START condition → Address (0x48) + R/W bit → ACK → Data byte (0x19) → STOP condition

**Simulation View:**

![Vivado Simulation](screenshots/Screenshot%202026-01-02%20at%2019.29.05.png)

_Vivado behavioral simulation showing waveforms and signal values_

### 3. Run UART Transmitter Testbench

```bash
iverilog -o uart_tb.vvp uart_tx.v tb_uart_tx.v
vvp uart_tb.vvp
gtkwave uart_tx.vcd
```

**Expected Waveform:** UART frame with start bit (0), 8 data bits (LSB first), stop bit (1) at configured baud rate

---

### For Hardware Implementation (FPGA Board)

1. Create a top-level module that instantiates:
   - I²C master logic (to be implemented)
   - `i2c_slave_dummy.v` (for simulation) or connect to real I²C sensor
   - `ascii_encoder.v`, `buildstring.v`
   - `uart_tx.v`
2. **Add Constraints File (XDC):**
   - Map `SCL`, `SDA` pins to I²C bus
   - Map `tx` pin to UART TX
   - Set clock constraints
3. **Run Implementation Flow:**
   - Synthesis → Implementation → Generate Bitstream
4. **Program Device:** Hardware Manager → Program Device

---

## Testing and Validation

### I²C Slave Testing

- Verify START condition detection (SDA falling while SCL high)
- Confirm address matching (0x48 + R/W bit)
- Check ACK generation by slave
- Validate data byte output (0x19)
- Verify STOP condition detection (SDA rising while SCL high)

### UART Testing

- Verify baud rate timing (clock division)
- Check frame format: 1 start bit + 8 data bits + 1 stop bit
- Confirm LSB-first bit ordering
- Validate idle state (tx = 1)

---

## Learning Resources

### Vivado Installation and Setup

- [Vivado Installation Guide Part 1](https://youtu.be/W8k0cfSOFbs?si=e_4kKj7fOBpXytX6)
- [Vivado Installation Guide Part 2](https://youtu.be/-U1OzeV9EKg?si=YT9s69aZx1oj1uqo)
- [First FPGA Project in Vivado](https://youtu.be/bw7umthnRYw)
- [Vivado Basic Implementation Playlist](https://www.youtube.com/playlist?list=PLmLQnr2Fjat0WpVSmZ76kkMtSWie2DBpQ)

### Protocol Learning

- **I²C:**
  - [I²C Basics](https://www.youtube.com/watch?v=OHzX6BCqVr8)
  - [I²C Intermediate](https://youtu.be/_bReVnQsiwg?si=isv9t6BjJJO4ykR2)
  - [I²C Implementation Playlist](https://youtube.com/playlist?list=PLIA9XWvqXXMzzO0g6bZTEtjTBv6sbKYpN&si=A2Mh8u2Ojac_JWYw)
- **UART:**
  - [UART Basics](https://youtu.be/NAYc1SoXGbQ?si=thPU9YME6vx897vg)
  - [UART Implementation Playlist](https://youtube.com/playlist?list=PLqPfWwayuBvPNEejEgA82Xq_n4gk8f0Kk&si=I4ECgYkW_tOOslzc)
  - [UART TX/RX Design](https://youtu.be/L62Ev3KOpFo?si=QSoAhtZv_DDi0Vew)

- **General Verilog:**
  - [Recommended Verilog Playlist](https://youtube.com/playlist?list=PLJ5C_6qdAvBELELTSPgzYkQg3HgclQh-5&si=BsM3Qucm3cVjgQK2)

---

## Contributors

### Ronil Borah — I²C Implementation

#### Problem Statement and Objectives

The primary objective was to implement an I²C slave device that simulates a temperature sensor. The slave needed to:

- Respond to a specific I²C address (0x48)
- Properly detect START and STOP conditions
- Handle address matching and ACK generation
- Transmit a fixed temperature value (25°C = 0x19 hex)
- Implement correct open-drain signaling for the SDA line

#### How I Tackled the Problem

**1. Understanding I²C Protocol Fundamentals**

- Studied I²C timing diagrams to understand START/STOP conditions
- Learned that START/STOP are asynchronous events (SDA transitions while SCL is HIGH)
- Recognized that I²C uses open-drain outputs requiring tri-state logic

**2. FSM Design Approach**

- Broke down the I²C slave operation into discrete states:
  - **IDLE**: Wait for START condition
  - **ADDR**: Receive 7-bit address + R/W bit
  - **ACK_ADDR**: Pull SDA low if address matches
  - **SEND_DATA**: Shift out temperature byte (MSB first)
  - **WAIT_ACK**: Release SDA and wait for master's ACK

**3. Critical Implementation Challenges and Solutions**

**Challenge 1: START/STOP Detection**

- **Problem**: Initial attempts clocked START/STOP detection on SCL edge, but these are asynchronous events
- **Solution**: Implemented separate combinational logic to detect SDA transitions while SCL is HIGH

```verilog
assign start_cond = (sda_prev == 1'b1) && (sda_in == 1'b0) && (scl == 1'b1);
assign stop_cond  = (sda_prev == 1'b0) && (sda_in == 1'b1) && (scl == 1'b1);
```

**Challenge 2: Open-Drain SDA Control**

- **Problem**: Initially tried to drive SDA as a regular output, causing bus contention in simulation
- **Solution**: Used `sda_oe` (output enable) signal - when HIGH, pull SDA low; when LOW, release to high-impedance
- Testbench models pull-up resistor with tri-state logic

**Challenge 3: Bit Timing and Sampling**

- **Problem**: Confusion about when to sample vs. drive SDA relative to SCL edges
- **Solution**: Master samples SDA on SCL rising edge, slave changes SDA on SCL falling edge

#### Proposed Solution and Implementation

**Files Created:**

- `i2c_slave_dummy.v` - FSM-based I²C slave with proper protocol handling
- `tb_i2c_slave_dummy.v` - Comprehensive testbench with I²C master tasks

**Key Features Implemented:**

- Finite State Machine with 5 states for protocol handling
- Asynchronous START/STOP detection independent of SCL clock
- Address comparison logic (7-bit address + R/W bit)
- Shift register for serial data transmission (MSB first)
- Proper SDA tri-state control using output enable signal
- Bit counter for tracking 8-bit transfers

**Validation and Testing:**

- Created testbench that acts as I²C master
- Implemented tasks: `i2c_start()`, `i2c_stop()`, `i2c_write_byte()`, `i2c_read_byte()`
- Verified waveforms showing correct START/STOP timing
- Confirmed ACK generation on address match
- Validated data byte transmission (0x19)

#### Changes from Initial Objectives

**Achieved:**

1. Complete I²C slave implementation with FSM
2. Proper START/STOP detection
3. Open-drain signaling with tri-state control
4. Address matching and ACK generation
5. Data byte transmission
6. Comprehensive testbench with waveform validation
7. Vivado project setup and behavioral simulation

**Limitations/Not Implemented:**

- Multi-byte register reads (only single-byte response)
- Clock stretching (slave holding SCL low)
- General call addressing
- 10-bit addressing mode
- I²C master module (only slave implemented)

#### Resources Used

**Primary Resources:**

- **Chatbots (ChatGPT/GitHub Copilot)**: Used when debugging issues, especially for:
  - Understanding START/STOP condition detection logic
  - Resolving tri-state/open-drain modeling in Verilog
  - Debugging FSM state transitions
  - Fixing testbench timing issues
  - For writing this

**YouTube Videos:**

- [I²C Basics](https://www.youtube.com/watch?v=OHzX6BCqVr8) - Understanding protocol fundamentals
- [I²C Implementation Playlist](https://youtube.com/playlist?list=PLIA9XWvqXXMzzO0g6bZTEtjTBv6sbKYpN&si=A2Mh8u2Ojac_JWYw) - FSM design patterns

**Development Tools:**

- Icarus Verilog for initial simulation and debugging
- GTKWave for waveform analysis
- Vivado for behavioral simulation and waveform capture

**Approach:**
When encountering issues, I relied on chatbots to:

1. Explain error messages and synthesis warnings
2. Suggest fixes for timing violations
3. Provide examples of proper I²C tri-state modeling
4. Debug testbench issues

---

### Shreya Meher — UART Implementation

#### Problem Statement and Objectives

The objective was to implement a reliable UART transmitter capable of serializing 8-bit data at a configurable baud rate and sending it using the standard frame format: 1 start bit (0), 8 data bits (LSB first), and 1 stop bit (1). The design needed to expose a simple handshake (`tx_start`, `tx_busy`), hold the line idle-high when not transmitting, and integrate cleanly with upstream ASCII and string-building modules.

#### How I Tackled the Problem

**1. Understanding UART Protocol Fundamentals**

- Reviewed UART frame structure and idle-line behavior (idle = HIGH)
- Clarified that transmission starts with a start bit (0), followed by 8 LSB-first data bits, and ends with a stop bit (1)
- Determined baud-rate timing from system clock using a divider

**2. FSM Design Approach**

- Broke the transmitter into four states:
  - **IDLE**: Line held HIGH, wait for `tx_start`
  - **START**: Drive start bit (0) for one baud period
  - **DATA**: Shift out 8 bits, LSB first, one per baud tick
  - **STOP**: Drive stop bit (1) for one baud period, then return to **IDLE**

**3. Critical Implementation Challenges and Solutions**

**Challenge 1: Accurate Baud-Tick Generation**

- **Problem**: Early versions produced jitter due to off-by-one errors in the divider
- **Solution**: Implemented a deterministic clock divider with a single-cycle `baud_tick` pulse; verified `BAUD_DIV = CLK_FREQ / BAUD_RATE` across test cases

**Challenge 2: Correct Bit Ordering**

- **Problem**: Initial shift logic sent MSB first, which is incorrect for UART
- **Solution**: Switched to LSB-first serialization using a right-shift register, sampling the LSB each baud tick

**Challenge 3: Back-to-Back Transmissions**

- **Problem**: Consecutive `tx_start` requests during `STOP` caused dropped frames
- **Solution**: Gated `tx_start` acceptance only in **IDLE** and exposed `tx_busy` so upstream logic waits until transmission completes

#### Proposed Solution and Implementation

**Files Implemented:**

- `uart_tx.v` — Parameterizable UART transmitter with FSM and baud generator
- `tb_uart_tx.v` — Testbench driving multiple data bytes and asserting timing correctness

**Key Features:**

- Clean FSM: **IDLE → START → DATA → STOP**
- Parameterized `CLK_FREQ` and `BAUD_RATE`; computed `BAUD_DIV`
- Single-cycle `baud_tick` drives state transitions and bit timing
- LSB-first shifting via a data register and bit counter
- `tx_busy` handshake to prevent overlapping transmissions
- Synchronous reset to a known idle state (line HIGH)

**Representative Snippets:**

```verilog
// FSM states
IDLE  // wait for tx_start, tx = 1
START // tx = 0 for one baud period
DATA  // shift out 8 bits, LSB first
STOP  // tx = 1 for one baud period

// Baud divider
BAUD_DIV = CLK_FREQ / BAUD_RATE; // e.g., 1_000_000 / 9600 ≈ 104
```

#### Validation and Testing

- Built a self-checking testbench that:
  - Pulses `tx_start` with various bytes (`'A'`, `'T'`, numeric digits)
  - Monitors `tx`, `tx_busy`, and bit timing aligned to `baud_tick`
  - Confirms start bit = 0, data bits LSB-first, stop bit = 1
- Generated VCDs and inspected waveforms in GTKWave to verify frame boundaries and inter-frame idle periods

#### Changes from Initial Objectives

**Achieved:**

1. Robust UART TX with parameterized baud rate
2. Deterministic baud tick generation and clean FSM transitions
3. LSB-first bit serialization with accurate timing
4. Handshake (`tx_busy`) to coordinate with upstream modules
5. Comprehensive testbench and waveform validation

**Limitations/Not Implemented:**

- No parity bit or configurable stop-bit length (fixed 1 stop bit)
- No hardware flow control (CTS/RTS)
- No transmit FIFO; relies on upstream rate control via `tx_busy`

#### Resources Used

**Primary References:**

- UART protocol tutorials and timing diagrams (see Learning Resources above)
- Waveform inspection with GTKWave for timing validation
- Chatbots (ChatGPT/GitHub Copilot) for debugging divider math and FSM edge cases

---

---

## Hardware Implementation on ZedBoard

This section provides a complete guide to implementing this project on the **Zynq ZedBoard (xc7z020)** using the Programmable Logic (PL) fabric only, without the ARM Processing System (PS).

### Target Hardware

- **Board:** Zynq ZedBoard (xc7z020clg484-1)
- **Implementation:** Pure FPGA (PL-only, no PS)
- **Clock Source:** 100 MHz onboard oscillator
- **Output Interface:** USB-UART bridge and GPIO headers

⚠️ **Note:** Ensure the ZedBoard clock configuration jumpers are in the default position to route the 100 MHz oscillator to the PL. Check jumpers JP7-JP11 if the clock is not functioning.

### Required External Components

⚠️ **MANDATORY for I²C operation:**

- **2 × 4.7 kΩ resistors** (pull-up resistors)
  - One for SDA line → 3.3V
  - One for SCL line → 3.3V

Without these pull-ups, the I²C bus will not function correctly due to the open-drain nature of I²C.

---

### Pre-Flight Checklist

Before starting hardware implementation, ensure you have:

- ✅ **Vivado Design Suite installed and licensed** (WebPACK edition is sufficient)
- ✅ **Board drivers installed** (Xilinx Cable Drivers for JTAG programming)
- ✅ **ZedBoard powers on** (check LD12 power LED - should be solid blue/green)
- ✅ **USB cables functional** (data cables, not charging-only cables)
  - One USB Mini-B for JTAG programming
  - One USB Micro-B for UART communication
- ✅ **Terminal software installed** (PuTTY, screen, or minicom)
- ✅ **Pull-up resistors acquired** (2× 4.7kΩ resistors, 1/4W or 1/8W)
- ✅ **Jumper wires** (if using breadboard for pull-up connections)
- ✅ **Breadboard** (optional, for easier pull-up resistor connections)

---

### Safety & Best Practices

⚠️ **IMPORTANT: Read Before Connecting Hardware**

#### ESD Protection

- **Use an anti-static wrist strap** when handling the board
- Touch a grounded metal surface before handling FPGA board
- Work on anti-static mat if available
- Store board in anti-static bag when not in use
- **Never touch pins while board is powered**

#### Power-On Sequence

1. **First:** Connect USB cables (JTAG and UART)
2. **Second:** Verify connections are secure
3. **Third:** Power on board using SW8 switch
4. **Never:** Hot-plug USB cables while board is powered

#### PMOD Connection Safety

- ⚠️ **NEVER connect or disconnect PMOD pins while board is powered**
- ⚠️ **NEVER apply voltage >3.3V to any PMOD pin**
- Always power off board before making PMOD connections
- Double-check wiring before powering on
- Use a multimeter to verify no short circuits before power-on

#### General Guidelines

- Keep liquids away from the board
- Ensure adequate ventilation (board may get warm during operation)
- Don't cover or block the heatsink on the Zynq chip
- Use regulated 12V power supply (included with board)
- Check for loose components or damaged traces before use

---

### Common Beginner Mistakes

**❌ Forgetting to press RESET after programming**

- **Solution:** Always press the center button (BTNC) after programming the FPGA
- The design requires a reset pulse to initialize all FSMs to their IDLE states

**❌ Using wrong USB cable (charging vs data)**

- **Symptom:** Device not detected in Vivado Hardware Manager or Device Manager
- **Solution:** Verify cables support data transfer (check with another device first)
- Both JTAG and UART ports require data-capable USB cables

**❌ Incorrect board jumper positions**

- **Symptom:** No clock signal, board doesn't program, or random behavior
- **Solution:** Check jumpers JP7-JP11 are in default positions (see ZedBoard manual page 18)
- Jumper JP7 should select "JTAG" mode
- Clock source jumpers should route 100 MHz oscillator to PL

**❌ Confusing PS (Processing System) vs PL (Programmable Logic)**

- **This project uses PL ONLY** - no ARM processor involvement
- Don't try to create a Zynq PS+PL design in Vivado
- Select "RTL Project" not "Zynq Project"
- Only the FPGA fabric is used; ignore PS-related wizards

**❌ Missing or incorrect pull-up resistors**

- **Symptom:** I²C communication fails, no data output
- **Solution:** Must have 4.7kΩ resistors from SDA→3.3V and SCL→3.3V
- Verify connections with multimeter (should read ~3.3V on idle bus)

**❌ Wrong serial port in terminal**

- **Symptom:** No output in terminal, even though FPGA is programmed
- **Solution:** Check Device Manager (Windows) or `ls /dev/tty*` (macOS/Linux)
- The UART port is **different** from the JTAG port

**❌ Not setting the top module**

- **Symptom:** Synthesis fails with "no top module found"
- **Solution:** Right-click on `sensor_hub_top` module and select "Set as Top"
- Note: File is named `sensor_hub_complete.v`, but module is `sensor_hub_top`

**❌ Attempting to run without trigger**

- **Symptom:** "Nothing happens after programming"
- **Solution:** Press RESET (BTNC), then press TRIGGER (BTNR) to start transmission
- Design is event-driven, not continuous

---

### Physical Pin Mapping

#### System Signals

| Signal    | Direction | ZedBoard Pin | Description                      | IOSTANDARD |
| --------- | --------- | ------------ | -------------------------------- | ---------- |
| `clk`     | Input     | Y9           | 100 MHz onboard clock            | LVCMOS33   |
| `rst`     | Input     | P16          | Push button (center button)      | LVCMOS33   |
| `trigger` | Input     | N15          | Push button (right button)       | LVCMOS33   |
| `uart_tx` | Output    | D4           | UART transmit to USB-UART bridge | LVCMOS33   |

#### I²C Bus (PMOD Connector JA)

| Signal | Direction | ZedBoard Pin | PMOD Pin | External Connection   |
| ------ | --------- | ------------ | -------- | --------------------- |
| `scl`  | Output    | E15          | JA2      | 4.7kΩ pull-up to 3.3V |
| `sda`  | Inout     | E16          | JA1      | 4.7kΩ pull-up to 3.3V |

**Note:** The PMOD pins can be changed based on availability. Ensure the XDC constraints match your physical connections.

---

### Physical Wiring Diagram

```
ZedBoard PMOD Header (JA)
┌─────────────────────────┐
│ JA1 (SDA) ──┬───────────┤ I²C Data (bidirectional)
│             │           │
│             └──[4.7kΩ]──┤── 3.3V (VCC)
│                         │
│ JA2 (SCL) ──┬───────────┤ I²C Clock
│             │           │
│             └──[4.7kΩ]──┤── 3.3V (VCC)
│                         │
│ GND ────────────────────┤ Ground
└─────────────────────────┘

USB-UART (Onboard)
├── TX ──→ PC (auto-connected via USB)
└── RX (not used)
```

---

### XDC Constraints File

Create `zedboard_sensor_hub.xdc` with the following content:

```xdc
# ============================================================================
# ZedBoard Sensor Hub Constraints
# ============================================================================

# System Clock (100 MHz)
set_property PACKAGE_PIN Y9 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.0 -name sys_clk [get_ports clk]

# Reset Button (Center button - BTNC)
set_property PACKAGE_PIN P16 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# Trigger Button (Right button - BTNR)
set_property PACKAGE_PIN N15 [get_ports trigger]
set_property IOSTANDARD LVCMOS33 [get_ports trigger]

# UART TX (USB-UART bridge)
set_property PACKAGE_PIN D4 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# I²C SCL (PMOD JA2)
set_property PACKAGE_PIN E15 [get_ports scl]
set_property IOSTANDARD LVCMOS33 [get_ports scl]

# I²C SDA (PMOD JA1)
set_property PACKAGE_PIN E16 [get_ports sda]
set_property IOSTANDARD LVCMOS33 [get_ports sda]

# Timing Constraints
set_input_delay -clock sys_clk -max 2.0 [get_ports rst]
set_input_delay -clock sys_clk -max 2.0 [get_ports trigger]
set_output_delay -clock sys_clk -max 2.0 [get_ports uart_tx]

# Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
```

⚠️ **Important:** Do NOT enable internal FPGA pull-ups/pull-downs for SDA/SCL. Use only external 4.7kΩ resistors.

---

### Vivado Project Setup (Step-by-Step)

#### 1. Create New Project

1. Open **Vivado Design Suite**
2. Click **Create Project**
3. Project name: `sensor_hub_zedboard`
4. Project location: Choose your workspace
5. Project type: **RTL Project**
6. ☑️ **Do not specify sources at this time**
7. Click **Next**

#### 2. Select Target Board

1. In the **Default Part** screen, select **Boards** tab
2. Search for: `ZedBoard`
3. Select: **ZedBoard Zynq Evaluation and Development Kit**
4. Part: `xc7z020clg484-1`
5. Click **Next** → **Finish**

#### 3. Add Source Files

1. Click **Add Sources** (or press Alt+A)
2. Select **Add or create design sources**
3. Click **Add Files**
4. Navigate to your project directory
5. Select **`sensor_hub_complete.v`** (this file contains all modules including the top module)
6. ☑️ **Copy sources into project**
7. Click **Finish**

⚠️ **Important:** The file is named `sensor_hub_complete.v`, but the top-level module inside is named `sensor_hub_top`. This is normal and expected.

#### 4. Set Top Module

1. In **Sources** window, right-click on **`sensor_hub_top`** (the module, not the file)
2. Select **Set as Top**
3. Verify the hierarchy shows `sensor_hub_top` as the root
4. All sub-modules (i2c_master, i2c_slave_dummy, uart_tx, etc.) should appear under it

#### 5. Add Constraints

1. Click **Add Sources**
2. Select **Add or create constraints**
3. Click **Create File**
4. File name: `zedboard_sensor_hub`
5. File type: **XDC**
6. Click **OK** → **Finish**
7. Copy the XDC content from above into this file

#### 6. Run Synthesis

1. Click **Run Synthesis** in Flow Navigator
2. Wait for completion (2-5 minutes)
3. ✅ Check for errors in the Messages window
4. Click **OK** when synthesis completes

#### 7. Run Implementation

1. Click **Run Implementation**
2. Wait for completion (3-7 minutes)
3. ✅ Verify no critical warnings
4. Review timing report:
   - All setup/hold times should be met
   - No negative slack

#### 8. Generate Bitstream

1. Click **Generate Bitstream**
2. Wait for bitstream generation (2-4 minutes)
3. ✅ Check for "Bitstream generation successful" message

#### 9. Program the FPGA

1. Connect ZedBoard via **USB JTAG** cable
2. Power on the board (SW8 switch)
3. Click **Open Hardware Manager**
4. Click **Auto Connect**
5. Right-click on the detected device (`xc7z020_1`)
6. Select **Program Device**
7. Bitstream file should auto-populate
8. Click **Program**
9. ✅ Wait for "Programming successful" message

---

### Serial Terminal Setup

To view the UART output, configure a serial terminal on your PC:

#### Using PuTTY (Windows)

1. Download and install [PuTTY](https://www.putty.org/)
2. Connection type: **Serial**
3. Serial line: `COM3` (check Device Manager for actual port)
4. Speed: **9600**
5. Click **Open**

#### Using screen (macOS/Linux)

```bash
# Find the device
ls /dev/tty.*                    # macOS
ls /dev/ttyUSB*                  # Linux

# Connect (replace with your device)
screen /dev/tty.usbserial-* 9600  # macOS
screen /dev/ttyUSB0 9600          # Linux

# Disconnect: Ctrl+A, then K, then Y
```

#### Using minicom (Linux)

```bash
sudo minicom -D /dev/ttyUSB0 -b 9600
```

#### Serial Port Settings

| Parameter    | Value |
| ------------ | ----- |
| Baud rate    | 9600  |
| Data bits    | 8     |
| Parity       | None  |
| Stop bits    | 1     |
| Flow control | None  |

---

### Running the Demo

1. **Power on the ZedBoard**
2. **Open serial terminal** at 9600 baud
3. **Press the RESET button** (center button - BTNC)
   - This initializes all FSM states
4. **Press the TRIGGER button** (right button - BTNR)
   - This starts the I²C read and UART transmission

**Expected Output:**

```
Temp = 25
```

Each press of the TRIGGER button will produce one line of output.

⚠️ **Note:** Push buttons are not debounced in hardware. For clean operation, press and release the trigger button deliberately. Rapid or noisy button presses may cause multiple triggers.

---

### Debugging Checklist

If the output doesn't appear or is incorrect, check the following:

#### ❌ No output in terminal

**Possible causes:**

- ✅ Wrong COM port selected
- ✅ Terminal not set to 9600 baud
- ✅ UART TX pin constraint incorrect
- ✅ Bitstream not programmed successfully
- ✅ Reset button not pressed after programming

**Solutions:**

- Verify COM port in Device Manager (Windows) or `ls /dev/tty*` (macOS/Linux)
- Double-check terminal settings (9600, 8N1)
- Re-verify XDC constraints match physical connections
- Re-program the device
- Press reset button, then trigger button

#### ❌ Garbage characters displayed

**Possible causes:**

- ✅ Clock frequency mismatch
- ✅ Wrong baud rate parameter
- ✅ Timing violations in design

**Solutions:**

- Verify clock constraint is 10.0ns (100 MHz)
- Check `uart_tx` module parameters: `CLK_FREQ = 100_000_000, BAUD = 9600`
- Review timing report for setup/hold violations
- Ensure no critical warnings in implementation

#### ❌ I²C transaction fails (no data)

**Possible causes:**

- ✅ Missing external pull-up resistors
- ✅ SDA/SCL lines swapped
- ✅ Wrong PMOD pins
- ✅ Short circuit or open connection

**Solutions:**

- **MANDATORY:** Connect 4.7kΩ resistors from SDA → 3.3V and SCL → 3.3V
- Verify physical wiring matches XDC constraints
- Check continuity with multimeter
- Measure voltage on SDA/SCL (should be ~3.3V when idle)

#### ❌ Output prints only once

**Expected behavior:**

- Design requires one TRIGGER press per output line
- This is intentional; not a bug

**If it doesn't repeat:**

- Button may need debouncing (add debounce circuit if needed)
- Verify trigger button connection
- Check FSM returns to IDLE state after transmission

#### ❌ Synthesis/Implementation errors

**Common issues:**

- ✅ Missing module declarations
- ✅ Port mismatch between modules
- ✅ Latch inference warnings

**Solutions:**

- Ensure all modules are in the same file or properly referenced
- Check all `always @(*)` blocks have complete case statements
- Review Vivado messages for specific errors

---

### Design Notes for VIVA/Presentation

**Key Points to Emphasize:**

1. **I²C Protocol Implementation:**
   - Open-drain signaling (never drive high, only pull low or release)
   - START condition: SDA falls while SCL is high
   - STOP condition: SDA rises while SCL is high
   - ACK/NACK mechanism for handshaking

2. **Dummy Slave Behavior:**
   - Returns fixed temperature (25°C)
   - Simplification: ignores master ACK after data transmission
   - Real sensor would support multiple reads and temperature updates

3. **UART Framing:**
   - Asynchronous communication (no shared clock)
   - Start bit (0), 8 data bits (LSB first), stop bit (1)
   - Baud rate generator ensures accurate timing

4. **FSM-Based Design:**
   - Clear state transitions
   - One-shot pulse generators for control signals
   - Prevents multiple triggers per event

5. **PL-Only Implementation:**
   - No ARM processor involvement
   - Demonstrates FPGA can replace microcontroller for simple sensor interfaces

**Intentional Simplifications:**

- No clock stretching (I²C advanced feature)
- No multi-byte reads
- No repeated START condition
- Fixed temperature value (not reading from real sensor)
- No UART receive path (TX only)

---

### Expected Questions & Answers

**Q: Is this fully I²C compliant?**  
**A:** Essential protocol phases are implemented correctly: START, address, ACK, data, STOP. Advanced features like clock stretching, 10-bit addressing, and multi-master arbitration are omitted for simplicity.

**Q: Why are external pull-ups required?**  
**A:** I²C is an open-drain bus. Devices can only pull the line LOW. Pull-up resistors are needed to return the line to HIGH when released. Without them, the line remains floating and communication fails.

**Q: Why not use the ARM processor (PS) on Zynq?**  
**A:** To demonstrate pure FPGA-based sensor interfacing. This shows that an FPGA alone can handle sensor protocols without a processor, which is useful for high-speed, deterministic applications.

**Q: How is the baud rate calculated?**  
**A:** `BAUD_DIV = CLK_FREQ / BAUD_RATE = 100,000,000 / 9600 = 10,416`. The UART divider counts to 10,416 before generating each bit timing tick.

**Q: What happens if I press trigger while transmission is in progress?**  
**A:** The FSM ignores the trigger signal when not in IDLE state. The design uses state-based control to prevent re-triggering during active transactions.

**Q: Can this read from a real temperature sensor?**  
**A:** Yes, with modifications. Replace the `i2c_slave_dummy` module with connections to external I²C sensor pins (like LM75 or TMP102). Ensure proper voltage levels and pull-ups are used.

---

### Final Verification Checklist

Before leaving the lab or demonstrating the project:

- ✅ Bitstream programmed successfully
- ✅ External 4.7kΩ pull-up resistors connected on SDA and SCL
- ✅ Serial terminal configured at 9600 baud, 8N1, no flow control
- ✅ Output displays "Temp = 25" when trigger is pressed
- ✅ Screenshots taken of:
  - Vivado project hierarchy
  - Implementation reports (timing, utilization)
  - Serial terminal output
  - GTKWave simulation waveforms (if available)
- ✅ Wiring diagram documented
- ✅ XDC file saved and backed up

---

### Resource Utilization

Typical resource usage on xc7z020 (from implementation reports):

| Resource        | Used | Available | Utilization |
| --------------- | ---- | --------- | ----------- |
| Slice LUTs      | ~450 | 53,200    | <1%         |
| Slice Registers | ~280 | 106,400   | <1%         |
| I/O             | 6    | 200       | 3%          |
| BUFG            | 1    | 32        | 3%          |

**Note:** This is a very small design suitable for educational purposes. Plenty of resources remain for expansion.

---

### Troubleshooting Hardware Issues

#### LED Indicators (if added)

For easier debugging, you can add LED indicators to the XDC and modify the top module:

```xdc
# Optional: Status LEDs
set_property PACKAGE_PIN T22 [get_ports led_i2c_busy]     # LD0
set_property PACKAGE_PIN T21 [get_ports led_uart_busy]    # LD1
set_property IOSTANDARD LVCMOS33 [get_ports led_i2c_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_uart_busy]
```

Add to top module:

```verilog
output wire led_i2c_busy,
output wire led_uart_busy

assign led_i2c_busy = i2c_busy;
assign led_uart_busy = uart_busy;
```

This helps visualize when each module is active.

#### Logic Analyzer / ILA

For advanced debugging, insert an Integrated Logic Analyzer (ILA):

1. In Vivado, **Tools** → **Set up Debug**
2. Select critical signals: `scl`, `sda`, `state`, `uart_tx`
3. Re-run implementation and generate bitstream
4. Use **Hardware Manager** to capture live waveforms

---

### Extension Ideas

Once the basic project works, consider these enhancements:

1. **Variable Temperature:**
   - Add up/down buttons to change temperature value
   - Display range: 0-99°C

2. **Multiple Sensors:**
   - Implement multiple I²C slaves with different addresses
   - Read and display values from each

3. **LCD Display:**
   - Add 16×2 character LCD via I²C (PCF8574 expander)
   - Display temperature locally without PC

4. **Real Sensor Integration:**
   - Connect actual LM75/TMP102 sensor
   - Read real temperature from environment

5. **Data Logging:**
   - Store readings in block RAM
   - Transmit history when requested

6. **Error Handling:**
   - Detect and report I²C NAK errors
   - Add timeout mechanisms
   - Display error messages on UART

---

### Conclusion

This hardware implementation guide provides everything needed to successfully deploy the sensor hub project on a ZedBoard. The design demonstrates:

- **Protocol Implementation:** I²C master and slave with proper timing
- **Interface Design:** UART communication with PC
- **FSM Control:** Clean state-based operation
- **FPGA Utilization:** Efficient use of programmable logic

The project serves as an excellent foundation for understanding sensor interfacing, serial protocols, and FPGA-based system design.

---

## Project Context

This project is part of a digital design course under the Phoenix Association focusing on serial communication protocols (I²C, UART, SPI) and FPGA implementation. The goal is to understand:

- Asynchronous serial communication (UART)
- Synchronous serial communication with multi-master capability (I²C)
- FSM-based protocol implementation
- Testbench development and waveform analysis
- Vivado simulation and synthesis workflow
- Hardware deployment on industry-standard FPGA boards
