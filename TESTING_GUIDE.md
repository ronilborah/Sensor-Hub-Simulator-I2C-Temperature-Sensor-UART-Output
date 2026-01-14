# Sensor Hub Testing Guide

## Prerequisites

Make sure you have Icarus Verilog and GTKWave installed:

### macOS (using Homebrew):

```bash
brew install icarus-verilog
brew install gtkwave
```

### Ubuntu/Debian:

```bash
sudo apt-get install iverilog gtkwave
```

## Quick Start

### Method 1: Using the test script (Easiest)

```bash
chmod +x run_test.sh
./run_test.sh
```

### Method 2: Manual commands

```bash
# Compile the design
iverilog -o sensor_hub_sim -g2012 sensor_hub_complete.v tb_sensor_hub.v

# Run simulation
vvp sensor_hub_sim

# View waveforms
gtkwave sensor_hub.vcd
```

## Expected Output

The simulation should display:

```
Received 11 characters:
Message: "Temp = 25\r\n"

✓ TEST PASSED: Correct message received!
```

## What the Testbench Does

1. **Generates 1 MHz clock** - System clock for the design
2. **Applies reset** - Initializes all modules
3. **Triggers sensor read** - Pulses the trigger signal
4. **Monitors I²C bus** - Watches SCL and SDA signals
5. **Decodes UART output** - Receives and decodes the 11-character message
6. **Verifies result** - Checks if "Temp = 25\r\n" was correctly transmitted

## Viewing Waveforms in GTKWave

### Recommended Signals to Add:

1. **Top Level:**

   - `clk` - System clock
   - `rst` - Reset signal
   - `trigger` - Start signal
   - `dut.state[2:0]` - FSM state (0=IDLE, 1=I2C, 2=WAIT_I2C, 3=UART_SEND, 4=WAIT_UART)

2. **I²C Signals:**

   - `scl` - I²C clock
   - `sda` - I²C data (bidirectional)
   - `dut.master.state[3:0]` - I²C Master state
   - `dut.slave.state[1:0]` - I²C Slave state

3. **UART Signals:**

   - `uart_tx` - UART transmit line
   - `dut.uart_busy` - UART busy flag
   - `dut.uart_start` - UART start trigger
   - `dut.idx[3:0]` - Character index (0-10)

4. **Data Signals:**
   - `dut.temp[7:0]` - Temperature read from I²C
   - `dut.temp_latched[7:0]` - Latched temperature value
   - `dut.ch[7:0]` - Current character being transmitted

### GTKWave Tips:

1. **Zoom to fit:** Press `Ctrl+Alt+F` or use View → Zoom → Zoom Fit
2. **Zoom in/out:** Use mouse wheel or +/- keys
3. **Change display format:** Right-click signal → Data Format → (Binary/Hex/ASCII/etc)
4. **Add signals:** Drag from Signal Search Tree to Signals window
5. **Group signals:** Select multiple signals → Right-click → Insert Comment/Blank

## Key Observations

### I²C Transaction:

- **START condition:** SDA falls while SCL high
- **Address byte:** 0x48 (slave address) + 1 (read bit) = 0x91
- **Slave ACK:** SDA pulled low by slave
- **Data byte:** 0x19 (25 decimal)
- **Master NACK:** SDA high (no more data needed)
- **STOP condition:** SDA rises while SCL high

### UART Transmission:

Each character takes ~1.04ms at 9600 baud:

- Start bit (0)
- 8 data bits (LSB first)
- Stop bit (1)

Characters sent: T, e, m, p, space, =, space, 2, 5, \r, \n

## Timing Analysis

- **I²C transaction:** ~50-100 microseconds
- **UART for 11 chars:** ~11.4 milliseconds (11 × 1.04ms)
- **Total operation:** ~12 milliseconds

## Troubleshooting

### No output in simulation:

- Check clock is running: Look for `clk` toggling
- Verify reset is released: `rst` should go to 0
- Check trigger pulse: `trigger` should pulse high briefly

### Wrong message received:

- Check `temp_latched` value is 25 (0x19)
- Verify FSM reaches UART_SEND state
- Check `idx` increments from 0 to 10

### Compilation errors:

- Ensure using SystemVerilog mode: `-g2012` flag
- Check all files are in same directory
- Verify file names match exactly

## Advanced Testing

To test with different temperatures, modify the slave module:

```verilog
localparam [7:0] TEMP_DATA = 8'd42;  // Change to any value 0-99
```

Then recompile and run the test again.
