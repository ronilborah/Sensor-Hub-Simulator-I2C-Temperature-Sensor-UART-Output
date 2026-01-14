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
    input  wire clk,      // System clock for synchronization
    input  wire rst,      // Reset
    input  wire scl,
    input  wire sda_in,
    output reg  sda_oe
);
    localparam [6:0] SLAVE_ADDR = 7'h48;
    localparam [7:0] TEMP_DATA  = 8'd25;

    reg [2:0] state;
    localparam IDLE = 3'd0, ADDR = 3'd1, ACK_ADDR = 3'd2, DATA = 3'd3, WAIT_ACK = 3'd4;
    
    reg [7:0] shift;
    reg [2:0] bit_cnt;
    reg [7:0] data_reg;
    
    // Synchronize SDA for START/STOP detection
    reg sda_sync1, sda_sync2, sda_sync3;
    reg scl_sync1, scl_sync2;
    
    always @(posedge clk) begin
        sda_sync1 <= sda_in;
        sda_sync2 <= sda_sync1;
        sda_sync3 <= sda_sync2;
        scl_sync1 <= scl;
        scl_sync2 <= scl_sync1;
    end
    
    wire start_cond = sda_sync3 && !sda_sync2 && scl_sync2;  // SDA falls while SCL high
    wire stop_cond  = !sda_sync3 && sda_sync2 && scl_sync2;  // SDA rises while SCL high
    wire scl_posedge = !scl_sync2 && scl_sync1;
    wire scl_negedge = scl_sync2 && !scl_sync1;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            bit_cnt <= 0;
            shift <= 0;
            data_reg <= 0;
        end else if (start_cond) begin
            state <= ADDR;
            bit_cnt <= 0;
            shift <= 0;
        end else if (stop_cond) begin
            state <= IDLE;
            bit_cnt <= 0;
        end else if (scl_posedge) begin
            case (state)
                ADDR: begin
                    shift <= {shift[6:0], sda_sync2};
                    if (bit_cnt == 7) begin
                        if (shift[7:1] == SLAVE_ADDR && shift[0] == 1'b1)
                            state <= ACK_ADDR;
                        else
                            state <= IDLE;  // Address mismatch
                        bit_cnt <= 0;
                    end else
                        bit_cnt <= bit_cnt + 1;
                end
                ACK_ADDR: begin
                    data_reg <= TEMP_DATA;
                    state <= DATA;
                    bit_cnt <= 0;
                end
                DATA: begin
                    if (bit_cnt == 7) begin
                        state <= WAIT_ACK;
                        bit_cnt <= 0;
                    end else
                        bit_cnt <= bit_cnt + 1;
                end
                WAIT_ACK: begin
                    // NOTE: A real slave would sample SDA here to check master ACK/NACK
                    // For this dummy sensor, we ignore it and always return to IDLE
                    // In production: if (sda_sync2 == 1'b0) continue else stop
                    state <= IDLE;  // Transaction complete
                end
            endcase
        end
    end

    // SDA output control - only change during SCL low
    reg sda_oe_reg;
    
    always @(posedge clk) begin
        if (rst)
            sda_oe_reg <= 0;
        else if (scl_negedge || !scl_sync2) begin  // Update only when SCL is low
            case (state)
                ACK_ADDR: sda_oe_reg <= 1'b1;  // Pull low for ACK
                DATA:     sda_oe_reg <= (data_reg[7-bit_cnt] == 1'b0);  // Pull low for 0 bits
                default:  sda_oe_reg <= 1'b0;  // Release (high-Z)
            endcase
        end
    end
    
    assign sda_oe = sda_oe_reg;
endmodule


/* ===================== I2C MASTER ===================== */
module i2c_master(
    input  wire clk,
    input  wire rst,
    input  wire start,
    input  wire sda_in,
    output reg  scl,
    output reg  sda_oe,
    output reg  sda_out,
    output reg  [7:0] data,
    output reg  done,
    output reg  busy,
    output reg  ack_error
);
    localparam [6:0] SLAVE_ADDR = 7'h48;
    localparam DIV = 250;  // 100kHz I²C at 100MHz clock
    reg [15:0] div;
    reg [1:0] scl_phase;  // 0=low_start, 1=low_end, 2=high_start, 3=high_end
    
    always @(posedge clk) begin
        if (rst || state == IDLE) begin
            div <= 0;
            scl_phase <= 0;
        end else if (div == DIV - 1) begin
            div <= 0;
            scl_phase <= scl_phase + 1;
        end else
            div <= div + 1;
    end
    
    // SCL generation: high during phase 2&3, low during 0&1
    always @(*) begin
        if (state == IDLE || state == PRE_START)
            scl = 1'b1;
        else if (state == START || state == STOP1 || state == STOP2)
            scl = 1'b1;  // Keep high for START/STOP conditions
        else
            scl = scl_phase[1];  // High when bit 1 is set (phase 2,3)
    end
    
    wire tick = (div == 0);
    wire scl_low_mid  = tick && (scl_phase == 2'd1);  // Middle of SCL low
    wire scl_high_mid = tick && (scl_phase == 2'd3);  // Middle of SCL high
    
    reg [3:0] state;
    localparam IDLE=0, PRE_START=1, START=2, ADDR=3, ACK1=4, RDATA=5, NACK=6, STOP1=7, STOP2=8, FINISH=9;
    reg [2:0] bit_cnt;
    reg [7:0] addr_shift, data_shift;
    reg start_latched;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            busy <= 0;
            ack_error <= 0;
            sda_oe <= 0;
            sda_out <= 1;
            bit_cnt <= 0;
            data <= 0;
            start_latched <= 0;
        end else begin
            // Default: done is single-cycle pulse
            done <= 0;
            
            // Latch start signal
            if (start && state == IDLE)
                start_latched <= 1;
            
            case (state)
                IDLE: begin
                    sda_oe <= 0;
                    sda_out <= 1;
                    ack_error <= 0;
                    busy <= 0;
                    if (start_latched) begin
                        start_latched <= 0;
                        state <= PRE_START;
                        addr_shift <= {SLAVE_ADDR, 1'b1};  // Read operation
                        bit_cnt <= 7;
                        busy <= 1;
                    end
                end
                
                PRE_START: begin  // Ensure SCL is high and SDA is high before START
                    sda_oe <= 0;
                    sda_out <= 1;
                    if (tick && scl_phase == 0)
                        state <= START;
                end
                
                START: begin  // START: SDA falls while SCL high
                    if (tick && scl_phase == 2) begin
                        sda_oe <= 1;
                        sda_out <= 0;  // Pull SDA low while SCL is high
                        state <= ADDR;
                    end
                end
                
                ADDR: begin  // Send address byte
                    if (scl_low_mid) begin
                        sda_out <= addr_shift[bit_cnt];
                        sda_oe <= 1;
                        if (bit_cnt == 0)
                            state <= ACK1;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end
                
                ACK1: begin  // Check slave ACK
                    if (scl_low_mid) begin
                        sda_oe <= 0;  // Release SDA
                    end else if (scl_high_mid) begin
                        if (sda_in != 0)  // Should be pulled low by slave
                            ack_error <= 1;
                        state <= RDATA;
                        bit_cnt <= 7;
                    end
                end
                
                RDATA: begin  // Read data byte
                    if (scl_low_mid) begin
                        sda_oe <= 0;  // Keep released for reading
                    end else if (scl_high_mid) begin
                        data_shift[bit_cnt] <= sda_in;
                        if (bit_cnt == 0)
                            state <= NACK;
                        else
                            bit_cnt <= bit_cnt - 1;
                    end
                end
                
                NACK: begin  // Send NACK (master done reading)
                    if (scl_low_mid) begin
                        sda_out <= 1;
                        sda_oe <= 1;  // Drive high (NACK)
                        state <= STOP1;
                    end
                end
                
                STOP1: begin  // STOP prep: pull SDA low while SCL low
                    if (scl_low_mid) begin
                        sda_out <= 0;
                        sda_oe <= 1;
                        state <= STOP2;
                    end
                end
                
                STOP2: begin  // STOP: SDA rises while SCL high
                    if (tick && scl_phase == 2) begin
                        sda_oe <= 0;  // Release SDA (rises to high)
                        data <= data_shift;
                        state <= FINISH;
                    end
                end
                
                FINISH: begin
                    done <= 1'b1;  // Single-cycle pulse
                    busy <= 0;
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
    // Proper open-drain: pull low when either device asserts OE
    assign sda = (sda_m_oe || sda_s_oe) ? 1'b0 : 1'bz;
    assign sda_in = sda;

    /* ---- I2C ---- */
    wire [7:0] temp;
    wire i2c_done;

    wire sda_m_out;
    wire i2c_ack_error;
    wire i2c_busy;
    
    i2c_master master(
        .clk(clk), .rst(rst), .start(i2c_start),
        .sda_in(sda_in), .scl(scl),
        .sda_oe(sda_m_oe), .sda_out(sda_m_out),
        .data(temp), .done(i2c_done),
        .busy(i2c_busy),
        .ack_error(i2c_ack_error)
    );

    i2c_slave_dummy slave(
        .clk(clk), .rst(rst),
        .scl(scl), .sda_in(sda_in), .sda_oe(sda_s_oe)
    );

    /* ---- UART + CONTROL FSM ---- */
    reg [3:0] idx;
    reg [7:0] temp_latched;
    wire [7:0] ch;
    wire uart_busy;
    reg uart_start;
    reg i2c_start;
    
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
        end else begin
            // Default: clear one-shot signals
            uart_start <= 0;
            i2c_start <= 0;
            
            case (state)
                S_IDLE: begin
                    idx <= 0;
                    if (trigger) begin
                        i2c_start <= 1;
                        state <= S_I2C;
                    end
                end
                
                S_I2C: begin
                    state <= S_WAIT_I2C;
                end
                
                S_WAIT_I2C: begin
                    if (i2c_done) begin  // done is now a single-cycle pulse
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