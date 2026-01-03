module ascii_encoder (
    input  wire [7:0] value,     // e.g. 25
    output wire [7:0] tens_ascii, // '2'
    output wire [7:0] ones_ascii  // '5'
);

    wire [7:0] tens;
    wire [7:0] ones;

    assign tens = value / 10;
    assign ones = value % 10;

    assign tens_ascii = 8'd48 + tens; // '0' = 48
    assign ones_ascii = 8'd48 + ones;

endmodule
