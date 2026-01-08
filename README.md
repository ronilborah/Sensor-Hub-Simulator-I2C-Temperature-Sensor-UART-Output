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

## Project Context

This project is part of a digital systems design course focusing on serial communication protocols (I²C, UART, SPI) and FPGA implementation. The goal is to understand:

- Asynchronous serial communication (UART)
- Synchronous serial communication with multi-master capability (I²C)
- FSM-based protocol implementation
- Testbench development and waveform analysis
- Vivado simulation and synthesis workflow
