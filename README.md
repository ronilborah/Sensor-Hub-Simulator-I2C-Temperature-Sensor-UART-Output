# Sensor Hub Simulator — I²C Temperature Sensor + UART Output

This repository implements a Verilog-based sensor-hub simulator: the FPGA logic acts as an I²C master, reads a fixed temperature from a dummy I²C slave, converts the value to ASCII, and transmits it over UART. The expected runtime output (serial terminal) is:

Temp = 25

Contents and key modules

- `ascii_encoder.v` — converts numeric values into ASCII bytes.
- `ascii_uart_sender.v` — sequences ASCII bytes and hands them to the UART transmitter.
- `buildstring.v` — helpers for building ASCII strings from numeric values.
- `i2c_slave_dummy.v` — simple I²C slave model that returns a fixed temperature (25 decimal / 0x19 hex).
- `tb_i2c_slave_dummy.v` — testbench for the I²C slave.
- `tb_ascii_uart_sender.v` — end-to-end testbench connecting I2C dummy -> ASCII builder -> UART TX.
- `uart_tx.v` — UART transmitter core (baud generator, FSM, shift register).
- `uart_tx_tb.v` — UART transmitter testbench.

Quick start — simulation (Icarus Verilog)

1. Install tools (macOS):

```bash
brew install icarus-verilog gtkwave
```

2. Example: run the UART transmitter testbench:

```bash
iverilog -o uart_tb.vvp uart_tx.v uart_tx_tb.v
vvp uart_tb.vvp
```

3. Example: run the full end-to-end testbench (I2C dummy + ASCII builder + UART):

```bash
iverilog -o full_tb.vvp ascii_encoder.v ascii_uart_sender.v buildstring.v i2c_slave_dummy.v tb_ascii_uart_sender.v uart_tx.v
vvp full_tb.vvp
```

4. View generated waveform VCD files with GTKWave:

```bash
gtkwave <file>.vcd
```

Notes for simulation

- Ensure the testbench writes a VCD (or `sim.out`) file — check the testbench for the VCD filename.
- If needed, edit the testbench to increase simulation time or add specific stimulus.

Vivado — behavioral simulation and hardware flow

1. Create a new RTL project in Vivado and add the Verilog sources from this repo.
2. For simulation only, set the top-level testbench as the simulation source and run: Flow Navigator -> Simulation -> Run Behavioral Simulation.
3. To inspect waveforms, use the Vivado waveform viewer; expand signals such as `SCL`, `SDA`, `tx`, `clk`, and `reset`.
4. To target a physical board: add an XDC constraints file mapping `SCL`, `SDA`, and `tx` to board pins, then run Synthesis -> Implementation -> Generate Bitstream -> Program Device.

Recording Vivado waveforms / media guidance

Recommended: QuickTime Player (macOS) or OBS Studio. Capture the Vivado window and waveform pane while running Behavioral Simulation.

Steps (brief):

1. Open or create the Vivado project and add repo sources.
2. Run Behavioral Simulation and prepare the waveform zoom region you want to capture.
3. Start screen recording and then run the simulation to generate the waveform.
4. Stop recording and save the MP4 under `docs/media/` named `<yourname>_vivado_run.mp4`.
5. Also include 1–3 PNG screenshots with zoomed-in waveforms under `docs/media/`.

Recording settings (suggested): 1920x1080, 30 fps, MP4 (H.264), no audio.

File and test expectations

- I2C: the waveform should show a START condition, address + R/W, ACK, data byte `0x19`, and STOP.
- UART: transmitted framed bytes should correspond to ASCII for the string "Temp = 25" (LSB-first bit order, 1 start bit, 8 data bits, 1 stop bit typical).

Project overview and architecture

Functional flow:

1. FPGA I2C master issues a read to the dummy sensor address.
2. `i2c_slave_dummy.v` ACKs and returns a fixed temperature byte (25 decimal).
3. ASCII builder modules convert the numeric temperature into the printable string.
4. UART transmitter serializes the ASCII bytes and sends them out on the `tx` pin.

Testing strategy

- Unit tests: `uart_tx_tb.v` and `tb_i2c_slave_dummy.v`.
- End-to-end: `tb_ascii_uart_sender.v` validates I2C read → ASCII conversion → UART transmit.
- Use GTKWave or Vivado waveform viewer to validate signals and timings.

Contributors and individual work (as requested)

- Ronil Borah — I²C implementation and Vivado project/simulation flow

  - Implemented and tested the I²C master behavior and validated START/STOP, ACK sampling, and SDA tri-state handling in simulation. Created Vivado project, ran behavioral simulations, captured waveforms, and prepared Vivado-related instructions.

- Shreya Meher — UART implementation
  - Implemented and/or verified the UART transmitter core, baud/tick generator, FSM, shift register, and testbench validation. Confirmed framing and LSB-first transmission.

Assistant notes (what I added)

- Initial documentation and run instructions were written and added to this repo under `docs/`.
- `docs/teammate_contribution_template.txt` is provided so each teammate can add a detailed contribution file.

How to document your contribution (fill and commit)

1. Copy the template in `docs/teammate_contribution_template.txt` to `docs/<yourname>_contribution.txt`.
2. Fill sections with technical details: files changed, tests run (exact commands), waveform references and screenshots, and time log.
3. Place media in `docs/media/` and reference the files in your contribution text.

Resources and recommended learning materials

- Vivado installation and first projects:

  - https://youtu.be/W8k0cfSOFbs?si=e_4kKj7fOBpXytX6
  - https://youtu.be/-U1OzeV9EKg?si=YT9s69aZx1oj1uqo
  - https://youtu.be/bw7umthnRYw
  - https://www.youtube.com/playlist?list=PLmLQnr2Fjat0WpVSmZ76kkMtSWie2DBpQ

- Protocol learning resources (I²C / UART / SPI):
  - UART basics: https://youtu.be/NAYc1SoXGbQ?si=thPU9YME6vx897vg
  - I²C basics: https://www.youtube.com/watch?v=OHzX6BCqVr8
  - SPI basics: https://youtu.be/AV0w0Ko7D6E?si=LeWXZZPq2TrwtU3f
  - Recommended playlist for overall Verilog learning: https://youtube.com/playlist?list=PLJ5C_6qdAvBELELTSPgzYkQg3HgclQh-5&si=BsM3Qucm3cVjgQK2

Suggested next improvements

- Add a `Makefile` with `make sim`, `make full`, and `make wave` targets to standardize simulations.
- Add a CI job that runs `iverilog` tests and archives VCD outputs for PR validation.
- Expand I2C dummy to allow configurable returned temperature and multi-register reads.

Contact / workflow

- After you fill your individual contribution file and add media, ping the maintainer to merge and finalize the project report.
