`timescale 1ns/1ps

module uart_tx_tb;

    reg clk = 0;
    reg rst = 1;
    reg tx_start = 0;
    reg [7:0] tx_data = 8'h55;   
    wire tx;
    wire tx_busy;

    uart_tx #(
        .CLK_FREQ(1_000_000),
        .BAUD(9600)
    ) dut (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(tx),
        .tx_busy(tx_busy)
    );

    // 1 MHz clock → 1 us period
    always #500 clk = ~clk;

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, uart_tx_tb);

        // reset
        #2000 rst = 0;

        // request transmission
        #3000;
        tx_start = 1;
        #1000;
        tx_start = 0;

        // wait until done
        wait (!tx_busy);
        #10000;

        $finish;
    end

endmodule
