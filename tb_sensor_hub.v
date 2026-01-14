`timescale 1ns/1ps

module tb_sensor_hub;

    // Clock and Reset
    reg clk;
    reg rst;
    reg trigger;
    
    // Outputs
    wire uart_tx;
    wire scl;
    wire sda;
    wire busy;
    
    // Internal signals for monitoring
    reg [7:0] uart_rx_data;
    reg [7:0] received_chars [0:15];
    integer char_count;
    
    // Instantiate DUT (Device Under Test)
    sensor_hub_top dut (
        .clk(clk),
        .rst(rst),
        .trigger(trigger),
        .uart_tx(uart_tx),
        .scl(scl),
        .sda(sda)
    );
    
    // Clock generation: 100 MHz (10 ns period) to match design
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 5ns half-period = 100MHz
    end
    
    // UART Receiver Task (to decode transmitted data)
    task uart_receive;
        integer i;
        begin
            // Wait for start bit (falling edge)
            @(negedge uart_tx);
            #(104167);  // Wait 1 bit time at 9600 baud (104.167 us)
            
            // Sample 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                #(104167);
                uart_rx_data[i] = uart_tx;
            end
            
            // Wait for stop bit
            #(104167);
            
            // Store received character
            received_chars[char_count] = uart_rx_data;
            $display("[%0t] UART RX: 0x%02h '%c'", $time, uart_rx_data, 
                     (uart_rx_data >= 32 && uart_rx_data < 127) ? uart_rx_data : ".");
            char_count = char_count + 1;
        end
    endtask
    
    // Monitor UART output
    initial begin
        char_count = 0;
        forever begin
            uart_receive();
        end
    end
    
    // Test stimulus
    initial begin
        // Initialize
        rst = 1;
        trigger = 0;
        
        // Generate VCD file for GTKWave
        $dumpfile("sensor_hub.vcd");
        $dumpvars(0, tb_sensor_hub);
        
        $display("========================================");
        $display("  Sensor Hub Testbench Started");
        $display("  Clock: 100 MHz, UART: 9600 baud");
        $display("========================================");
        
        // Reset sequence
        #2000;
        rst = 0;
        $display("[%0t] Reset released", $time);
        
        // Wait a bit
        #5000;
        
        // Trigger temperature read
        $display("[%0t] Triggering I2C read...", $time);
        trigger = 1;
        #1000;
        trigger = 0;
        
        // Wait for I2C transaction and UART transmission to complete
        // I2C takes ~100us, UART for 11 chars @ 9600 baud takes ~11ms
        #15_000_000;  // 15ms should be enough
        
        // Display results
        $display("\n========================================");
        $display("  Transmission Complete");
        $display("========================================");
        $display("Received %0d characters:", char_count);
        
        // Print received message
        $write("Message: \"");
        for (integer j = 0; j < char_count; j = j + 1) begin
            if (received_chars[j] >= 32 && received_chars[j] < 127)
                $write("%c", received_chars[j]);
            else if (received_chars[j] == 8'h0D)
                $write("\\r");
            else if (received_chars[j] == 8'h0A)
                $write("\\n");
            else
                $write("?");
        end
        $write("\"\n");
        
        // Verify expected message: "Temp = 25\r\n"
        $display("\n========================================");
        $display("  Verification");
        $display("========================================");
        
        if (char_count == 11) begin
            if (received_chars[0] == "T" &&
                received_chars[1] == "e" &&
                received_chars[2] == "m" &&
                received_chars[3] == "p" &&
                received_chars[4] == " " &&
                received_chars[5] == "=" &&
                received_chars[6] == " " &&
                received_chars[7] == "2" &&
                received_chars[8] == "5" &&
                received_chars[9] == 8'h0D &&
                received_chars[10] == 8'h0A) begin
                $display("✓ TEST PASSED: Correct message received!");
            end else begin
                $display("✗ TEST FAILED: Message content incorrect");
            end
        end else begin
            $display("✗ TEST FAILED: Expected 11 characters, got %0d", char_count);
        end
        
        $display("\n========================================");
        $display("  Simulation Complete");
        $display("========================================");
        
        #1000;
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #20_000_000;  // 20ms timeout
        $display("\n✗ ERROR: Simulation timeout!");
        $finish;
    end
    
    // Monitor key signals
    initial begin
        $monitor("[%0t] State: busy=%b, scl=%b, sda=%b, uart_tx=%b", 
                 $time, dut.state, scl, sda, uart_tx);
    end

endmodule
