`timescale 1ns/1ps

module ascii_uart_sender (
    input  wire clk,
    input  wire rst,
    input  wire start_send,   // 1-cycle pulse after I2C read
    output wire uart_tx
);

    reg        tx_start;
    reg [7:0]  tx_data;
    wire       tx_busy;

    // UART TX instantiation
    uart_tx #(
        .CLK_FREQ(1_000_000),
        .BAUD(9600)
    ) uart_inst (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

    // Message: "Temp = 25\r\n"
    reg [7:0] msg [0:10];

    initial begin
        msg[0]  = "T";
        msg[1]  = "e";
        msg[2]  = "m";
        msg[3]  = "p";
        msg[4]  = " ";
        msg[5]  = "=";
        msg[6]  = " ";
        msg[7]  = "2";
        msg[8]  = "5";
        msg[9]  = 8'h0D; // CR
        msg[10] = 8'h0A; // LF
    end

    localparam IDLE = 2'd0,
               SEND = 2'd1,
               WAIT = 2'd2;

    reg [1:0] state;
    reg [3:0] idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            idx      <= 0;
            tx_start <= 1'b0;
            tx_data  <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    tx_start <= 1'b0;
                    idx <= 0;
                    if (start_send)
                        state <= SEND;
                end

                SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= msg[idx];
                        tx_start <= 1'b1;
                        state    <= WAIT;
                    end
                end

                WAIT: begin
                    tx_start <= 1'b0;
                    if (!tx_busy) begin
                        if (idx == 10)
                            state <= IDLE;
                        else begin
                            idx   <= idx + 1'b1;
                            state <= SEND;
                        end
                    end
                end
            endcase
        end
    end

endmodule