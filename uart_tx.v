`timescale 1ns/1ps

module uart_tx (
    input  wire clk,
    input  wire rst,
    input  wire tx_start,
    input  wire [7:0] tx_data,
    output reg  tx,
    output reg  tx_busy
);

    // --------------------------------------------------
    // Timing parameters
    // --------------------------------------------------
    parameter CLK_FREQ = 1_000_000;   // 1 MHz
    parameter BAUD     = 9600;
    localparam BAUD_DIV = CLK_FREQ / BAUD;

    // --------------------------------------------------
    // Baud tick generator
    // --------------------------------------------------
    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg baud_tick;

    // --------------------------------------------------
    // FSM state encoding
    // --------------------------------------------------
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0] state;

    // --------------------------------------------------
    // Data handling
    // --------------------------------------------------
    reg [7:0] shift_reg;
    reg [2:0] bit_idx;

    // --------------------------------------------------
    // Baud tick logic
    // --------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt  <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt  <= 0;
                baud_tick <= 1;
            end else begin
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= 0;
            end
        end
    end

    // --------------------------------------------------
    // UART TX FSM
    // --------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            tx        <= 1'b1;   // idle line high
            tx_busy   <= 1'b0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)

                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        bit_idx   <= 3'd0;
                        state     <= START;
                        tx_busy   <= 1'b1;
                    end
                end

                START: begin
                    tx    <= 1'b0;   // start bit
                    state <= DATA;
                end

                DATA: begin
                    tx <= shift_reg[bit_idx];  // LSB first
                    if (bit_idx == 3'd7)
                        state <= STOP;
                    else
                        bit_idx <= bit_idx + 1;
                end

                STOP: begin
                    tx    <= 1'b1;   // stop bit
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
