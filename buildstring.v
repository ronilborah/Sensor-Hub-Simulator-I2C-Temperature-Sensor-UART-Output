module buildstring (
    input  wire [7:0] value,
    input  wire [3:0] index,   // selects which character
    output reg  [7:0] char_out
);

    wire [7:0] tens_ascii, ones_ascii;

    ascii_encoder enc (
        .value(value),
        .tens_ascii(tens_ascii),
        .ones_ascii(ones_ascii)
    );

    always @(*) begin
        case (index)
            4'd0:  char_out = "T";
            4'd1:  char_out = "e";
            4'd2:  char_out = "m";
            4'd3:  char_out = "p";
            4'd4:  char_out = " ";
            4'd5:  char_out = "=";
            4'd6:  char_out = " ";
            4'd7:  char_out = tens_ascii;
            4'd8:  char_out = ones_ascii;
            4'd9:  char_out = 8'h0D; // \r
            4'd10: char_out = 8'h0A; // \n
            default: char_out = 8'h00;
        endcase
    end

endmodule
