module i2c_slave_dummy (
    input  wire scl,      // I2C clock from master
    input  wire sda_in,    // SDA input
    output wire sda_oe,    // SDA output enable (1 = pull low)
    input  wire rst_n      // active-low reset
);

    // -------------------------------------------------
    // Parameters
    // -------------------------------------------------
    localparam [6:0] SLAVE_ADDR = 7'h48; // Dummy address
    localparam [7:0] TEMP_DATA  = 8'd25; // 25°C

    // -------------------------------------------------
    // FSM states
    // -------------------------------------------------
    typedef enum logic [2:0] {
        IDLE      = 3'd0,
        ADDR      = 3'd1,
        ACK_ADDR  = 3'd2,
        SEND_DATA = 3'd3,
        WAIT_ACK  = 3'd4
    } state_t;

    state_t state, next_state;

    // -------------------------------------------------
    // Internal registers
    // -------------------------------------------------
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic sda_prev;

    // -------------------------------------------------
    // START / STOP detection (ASYNCHRONOUS – IMPORTANT)
    // -------------------------------------------------
    wire start_cond;
    wire stop_cond;

    assign start_cond = (sda_prev == 1'b1) && (sda_in == 1'b0) && (scl == 1'b1);
    assign stop_cond  = (sda_prev == 1'b0) && (sda_in == 1'b1) && (scl == 1'b1);

    // Track SDA transitions (not tied to SCL!)
    always @(posedge sda_in or negedge sda_in or negedge rst_n) begin
        if (!rst_n)
            sda_prev <= 1'b1;
        else
            sda_prev <= sda_in;
    end

    // -------------------------------------------------
    // FSM state register (clocked by SCL)
    // -------------------------------------------------
    always @(posedge scl or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------
    // FSM next-state logic
    // -------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (start_cond)        next_state = ADDR;
            ADDR:      if (bit_cnt == 3'd7)   next_state = ACK_ADDR;
            ACK_ADDR:                          next_state = SEND_DATA;
            SEND_DATA: if (bit_cnt == 3'd7)   next_state = WAIT_ACK;
            WAIT_ACK:  if (stop_cond)         next_state = IDLE;
            default:                           next_state = IDLE;
        endcase
    end

    // -------------------------------------------------
    // Bit counter and shift register
    // -------------------------------------------------
    always @(posedge scl or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                ADDR: begin
                    shift_reg <= {shift_reg[6:0], sda_in};
                    bit_cnt   <= bit_cnt + 1'b1;
                end
                ACK_ADDR: begin
                    bit_cnt   <= 3'd0;
                    shift_reg <= TEMP_DATA;
                end
                SEND_DATA: begin
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    bit_cnt   <= bit_cnt + 1'b1;
                end
                default: bit_cnt <= 3'd0;
            endcase
        end
    end

    // -------------------------------------------------
    // Open-drain SDA control
    // -------------------------------------------------
    assign sda_oe =
        (state == ACK_ADDR) ? 1'b1 :
        (state == SEND_DATA && shift_reg[7] == 1'b0) ? 1'b1 :
        1'b0;

endmodule