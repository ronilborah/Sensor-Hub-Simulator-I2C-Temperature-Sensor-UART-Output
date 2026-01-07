# Sensor Hub Simulator — I²C Temperature Sensor + UART Output

This repository implements a Verilog-based sensor-hub simulator where an FPGA reads temperature data from an I²C temperature sensor (simulated by a dummy slave module), converts the value to ASCII, and transmits it over UART to a PC terminal.

**Expected Output:** `Temp = 25`

---

## 📁 Repository Contents

### Core Modules

- **`i2c_slave_dummy.v`** — I²C slave device that simulates a temperature sensor, responds to address `0x48` and returns a fixed temperature value (25°C / 0x19 hex)
- **`tb_i2c_slave_dummy.v`** — Testbench for I²C slave module with START/STOP conditions and byte transfer validation
- **`uart_tx.v`** — UART transmitter with baud rate generator, FSM-based transmission control, and shift register
- **`tb_uart_tx.v`** — Testbench for UART transmitter module
- **`ascii_encoder.v`** — Converts binary temperature value to ASCII digit characters (tens and ones place)
- **`buildstring.v`** — Builds the complete ASCII string "Temp = 25\r\n" for UART transmission

---

## � System Architecture and Data Flow

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

## 💻 Detailed Code Explanations

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

## �🚀 Quick Start — Simulation with Icarus Verilog

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

### 3. Run UART Transmitter Testbench

```bash
iverilog -o uart_tb.vvp uart_tx.v tb_uart_tx.v
vvp uart_tb.vvp
gtkwave uart_tx.vcd
```

**Expected Waveform:** UART frame with start bit (0), 8 data bits (LSB first), stop bit (1) at configured baud rate

---

## 🔧 Vivado Setup and Simulation

### For Simulation (No Hardware Required)

1. **Launch Vivado** and create a new RTL project
2. **Add Design Sources:**
   - `i2c_slave_dummy.v`
   - `uart_tx.v`
   - `ascii_encoder.v`
   - `buildstring.v`
3. **Add Simulation Sources:**
   - `tb_i2c_slave_dummy.v`
   - `tb_uart_tx.v`
4. **Run Behavioral Simulation:**
   - Flow Navigator → Simulation → Run Behavioral Simulation
5. **Inspect Waveforms:**
   - Add signals: `SCL`, `SDA`, `tx`, `clk`, `reset`
   - Zoom to regions showing I²C transactions or UART frames

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

**Note:** You do **not** need to create separate files for Vivado — just add the existing `.v` files to your Vivado project as shown above.

---

## 📹 Recording Vivado Simulation (Optional)

**Tools:** QuickTime Player (macOS) or OBS Studio

**Steps:**

1. Open Vivado project and run Behavioral Simulation
2. Set up waveform view with key signals (SCL, SDA, tx, clk)
3. Start screen recording
4. Run simulation and zoom to interesting waveform regions
5. Stop recording and save as MP4

**Settings:** 1920×1080, 30fps, H.264, no audio

**Location:** Save recordings/screenshots in `screenshots/` folder with descriptive names

---

## 🧪 Testing and Validation

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

## 📚 Learning Resources

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

## 👥 Contributors

### Ronil Borah — I²C Implementation

**Contributions:**

- Implemented `i2c_slave_dummy.v` module with FSM-based I²C protocol handling
- Designed proper START/STOP condition detection (asynchronous, SCL-independent)
- Implemented SDA tri-state control and open-drain signaling
- Created `tb_i2c_slave_dummy.v` testbench with I²C transaction tasks
- Validated I²C timing and ACK/NACK behavior in simulation
- Set up Vivado project and ran behavioral simulations
- Captured and analyzed I²C waveforms in Vivado

**Key Technical Details:**

- Used separate FSM states for IDLE, ADDR, ACK_ADDR, SEND_DATA, WAIT_ACK
- Implemented shift register for serial-to-parallel conversion
- Proper handling of SDA sampling on SCL rising edge
- ACK generation by pulling SDA low

### Shreya Meher — UART Implementation

_Shreya will add her contribution details here_

---

## 🔮 Future Improvements

- Add I²C master module to complete full system integration
- Implement multi-byte I²C read/write transactions
- Add configurable temperature values (not fixed at 25)
- Create Makefile with simulation targets (`make sim`, `make wave`)
- Add constraints file templates for common FPGA boards (Zynq, Artix-7)
- Implement UART receiver for bidirectional communication

---

## 📝 Project Context

This project is part of a digital systems design course focusing on serial communication protocols (I²C, UART, SPI) and FPGA implementation. The goal is to understand:

- Asynchronous serial communication (UART)
- Synchronous serial communication with multi-master capability (I²C)
- FSM-based protocol implementation
- Testbench development and waveform analysis
- Vivado simulation and synthesis workflow

---

**License:** MIT (or specify your license)  
**Course:** Digital Systems Design  
**Institution:** (Add your institution name)
