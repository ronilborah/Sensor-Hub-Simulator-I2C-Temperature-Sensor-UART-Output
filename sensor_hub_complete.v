`timescale 1ns/1ps
// ============================================================================
// Mini Project 1 : Sensor Hub Simulator
// Correct FSM-based I2C Master + Dummy Slave + UART
// ============================================================================

/* ===================== ASCII ENCODER ===================== */
module ascii_encoder(
    input  wire [7:0] value,
    output wire [7:0] tens_ascii,
    output wire [7:0] ones_ascii
);
    assign tens_ascii = 8'd48 + (value / 10);
    assign ones_ascii = 8'd48 + (value % 10);
endmodule


/* ===================== STRING BUILDER ===================== */
module buildstring(
    input  wire [7:0] value,
    input  wire [3:0] index,
    output reg  [7:0] char_out
);
    wire [7:0] t, o;
    ascii_encoder enc(.value(value), .tens_ascii(t), .ones_ascii(o));

    always @(*) begin
        case (index)
            4'd0:  char_out = "T";
            4'd1:  char_out = "e";
            4'd2:  char_out = "m";
            4'd3:  char_out = "p";
            4'd4:  char_out = " ";
            4'd5:  char_out = "=";
            4'd6:  char_out = " ";
            4'd7:  char_out = t;
            4'd8:  char_out = o;
            4'd9:  char_out = 8'h0D;
            4'd10: char_out = 8'h0A;
            default: char_out = 8'h00;
        endcase
    end
endmodule


/* ===================== UART TX ===================== */
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 9600
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire [7:0] data,
    output reg  tx,
    output reg  busy
);
    localparam DIV = CLK_FREQ / BAUD;
    reg [$clog2(DIV)-1:0] cnt;
    reg tick;

    always @(posedge clk) begin
        if (rst) begin cnt <= 0; tick <= 0; end
        else begin
            cnt  <= (cnt == DIV-1) ? 0 : cnt + 1;
            tick <= (cnt == DIV-1);
        end
    end

    reg [9:0] shifter;
    reg [3:0] bitn;

    always @(posedge clk) begin
        if (rst) begin
            tx <= 1'b1; busy <= 1'b0; bitn <= 0;
        end else if (start && !busy) begin
            shifter <= {1'b1, data, 1'b0};
            busy <= 1'b1; bitn <= 0;
        end else if (busy && tick) begin
            tx <= shifter[bitn];
            bitn <= bitn + 1;
            if (bitn == 9) busy <= 1'b0;
        end
    end
endmodule


/* ===================== I2C DUMMY SLAVE ===================== */
module i2c_slave_dummy(
    input  wire scl,
    input  wire sda_in,
    output reg  sda_oe
);
    localparam [6:0] SLAVE_ADDR = 7'h48;
    localparam [7:0] TEMP_DATA  = 8'd25;

    reg [1:0] state;
    localparam ADDR = 2'd0, ACK_ADDR = 2'd1, DATA = 2'd2, WAIT_ACK = 2'd3;
    
    reg [7:0] shift;
    reg [2:0] bit_cnt;
    reg [7:0] data_reg;
    reg sda_prev;
    wire start_cond, stop_cond;
    
    assign start_cond = sda_prev && !sda_in && scl;
    assign stop_cond  = !sda_prev && sda_in && scl;
    
    always @(posedge sda_in or negedge sda_in) sda_prev <= sda_in;

    always @(posedge scl or posedge start_cond) begin
        if (start_cond) begin
            state <= ADDR;
            bit_cnt <= 0;
            shift <= 0;
        end else begin
            case (state)
                ADDR: begin
                    shift <= {shift[6:0], sda_in};
                    if (bit_cnt == 7) begin
                        if (shift[7:1] == SLAVE_ADDR && shift[0] == 1'b1)
                            state <= ACK_ADDR;
                        bit_cnt <= 0;
                    end else
                        bit_cnt <= bit_cnt + 1;
                end
                ACK_ADDR: begin
                    data_reg <= TEMP_DATA;
                    state <= DATA;
                end
                DATA: begin
                    if (bit_cnt == 7)
                        state <= WAIT_ACK;
                    else
                        bit_cnt <= bit_cnt + 1;
                end
            endcase
        end
    end

    always @(*) begin
        case (state)
            ACK_ADDR: sda_oe = 1'b1;
            DATA:     sda_oe = (data_reg[7-bit_cnt] == 1'b0);
            default:  sda_oe = 1'b0;
        endcase
    end
endmodule


/* ===================== I2C MASTER ===================== */
module i2c_master(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire sda_in,
    output reg  scl,
    output reg  sda_oe,
    output reg  [7:0] data,
    output reg  done
);
    localparam [6:0] SLAVE_ADDR = 7'h48;
    localparam DIV = 250;
    reg [15:0] div;
    reg [1:0] scl_phase;
    
    always @(posedge clk) begin
        if (rst || state == IDLE) begin
            div <= 0; scl_phase <= 0;
        end else if (div == DIV) begin
            div <= 0;
            scl_phase <= scl_phase + 1;
        end else
            div <= div + 1;
    end
    
    always @(*) scl = (state == IDLE || state == START || state == STOP) ? 1'b1 : scl_phase[1];
    wire tick = (div == 0);
    
    reg [3:0] state;
    localparam IDLE=0, START=1, ADDR=2, ACK1=3, RDATA=4, NACK=5, STOP=6, FINISH=7;
    reg [2:0] bit_cnt;
    reg [7:0] addr_shift, data_shift;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            sda_oe <= 0;
            bit_cnt <= 0;
            data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    sda_oe <= 0;
                    if (start) begin
                        state <= START;
                        addr_shift <= {SLAVE_ADDR, 1'b1};
                        bit_cnt <= 7;
                    end
                end
                
                START: begin
                    if (tick && scl_phase == 2) begin
                        sda_oe <= 1'b1;
                        state <= ADDR;
                    end
                end
                
                ADDR: begin
                    if (tick && scl_phase == 0) begin
                        sda_oe <= !addr_shift[bit_cnt];
                        if (bit_cnt == 0)
                            state <= ACK1;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end
                
                ACK1: begin
                    if (tick && scl_phase == 0) begin
                        sda_oe <= 0;
                        state <= RDATA;
                        bit_cnt <= 7;
                    end
                end
                
                RDATA: begin
                    if (tick && scl_phase == 2) begin
                        data_shift[bit_cnt] <= sda_in;
                        if (bit_cnt == 0)
                            state <= NACK;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end
                
                NACK: begin
                    if (tick && scl_phase == 0) begin
                        sda_oe <= 1'b1;
                        state <= STOP;
                    end
                end
                
                STOP: begin
                    if (tick && scl_phase == 2) begin
                        sda_oe <= 0;
                        data <= data_shift;
                        state <= FINISH;
                    end
                end
                
                FINISH: begin
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule


/* ===================== TOP LEVEL ===================== */
module sensor_hub_top(
    input  wire clk,
    input  wire rst,
    input  wire trigger,
    output wire uart_tx,
    output wire scl,
    inout  wire sda
);
    /* ---- OPEN DRAIN ---- */
    wire sda_m_oe, sda_s_oe;
    wire sda_in;
    assign sda = (sda_m_oe || sda_s_oe) ? 1'b0 : 1'bz;
    assign sda_in = sda;

    /* ---- I2C ---- */
    wire [7:0] temp;
    wire i2c_done;

    i2c_master master(
        .clk(clk), .rst(rst), .start(i2c_start),
        .sda_in(sda_in), .scl(scl),
        .sda_oe(sda_m_oe),
        .data(temp), .done(i2c_done)
    );

    i2c_slave_dummy slave(
        .scl(scl), .sda_in(sda_in), .sda_oe(sda_s_oe)
    );

    /* ---- UART + CONTROL FSM ---- */
    reg [3:0] idx;
    reg [7:0] temp_latched;
    wire [7:0] ch;
    wire uart_busy;
    reg uart_start;
    reg i2c_start;
    reg i2c_done_latch;
    
    buildstring bs(.value(temp_latched), .index(idx), .char_out(ch));

    uart_tx uart(
        .clk(clk), .rst(rst),
        .start(uart_start),
        .data(ch),
        .tx(uart_tx),
        .busy(uart_busy)
    );

    reg [2:0] state;
    localparam S_IDLE=0, S_I2C=1, S_WAIT_I2C=2, S_UART_SEND=3, S_WAIT_UART=4;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            idx <= 0;
            uart_start <= 0;
            i2c_start <= 0;
            temp_latched <= 0;
            i2c_done_latch <= 0;
        end else begin
            uart_start <= 0;
            i2c_start <= 0;
            
            // Latch i2c_done (from different clock domain)
            if (i2c_done) i2c_done_latch <= 1;
            
            case (state)
                S_IDLE: begin
                    idx <= 0;
                    i2c_done_latch <= 0;
                    if (trigger) begin
                        i2c_start <= 1;
                        state <= S_I2C;
                    end
                end
                
                S_I2C: begin
                    state <= S_WAIT_I2C;
                end
                
                S_WAIT_I2C: begin
                    if (i2c_done_latch) begin
                        temp_latched <= temp;
                        uart_start <= 1;
                        state <= S_UART_SEND;
                    end
                end
                
                S_UART_SEND: begin
                    state <= S_WAIT_UART;
                end
                
                S_WAIT_UART: begin
                    if (!uart_busy) begin
                        if (idx < 10) begin
                            idx <= idx + 1;
                            uart_start <= 1;
                            state <= S_UART_SEND;
                        end else
                            state <= S_IDLE;
                    end
                end
            endcase
        end
    end
endmodule