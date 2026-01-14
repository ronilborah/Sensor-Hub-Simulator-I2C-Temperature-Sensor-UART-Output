#!/bin/bash

# ============================================
# Sensor Hub Test Script
# ============================================

echo "=========================================="
echo "  Compiling Verilog Design"
echo "=========================================="

# Compile with Icarus Verilog
iverilog -o sensor_hub_sim \
    -g2012 \
    sensor_hub_complete.v \
    tb_sensor_hub.v

if [ $? -ne 0 ]; then
    echo "✗ Compilation failed!"
    exit 1
fi

echo "✓ Compilation successful"
echo ""

echo "=========================================="
echo "  Running Simulation"
echo "=========================================="

# Run simulation
vvp sensor_hub_sim

if [ $? -ne 0 ]; then
    echo "✗ Simulation failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Opening Waveform Viewer"
echo "=========================================="
echo "VCD file: sensor_hub.vcd"
echo "Starting GTKWave..."

# Open GTKWave
gtkwave sensor_hub.vcd &

echo ""
echo "✓ Done! Check GTKWave for waveforms."
