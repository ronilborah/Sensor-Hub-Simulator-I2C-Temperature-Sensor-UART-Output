`timescale 1ns/1ps

module tb_i2c_slave_dummy;

    reg  scl;
    reg  sda_drv;   // master pulls SDA low when =1
    wire sda;
    reg  rst_n;

    wire sda_oe;

    // DUT
    i2c_slave_dummy dut (
        .scl    (scl),
        .sda_in (sda),
        .sda_oe (sda_oe),
        .rst_n  (rst_n)
    );

    // -------------------------------------------------
    // Correct open-drain SDA modeling
    // -------------------------------------------------
    assign sda = (sda_drv || sda_oe) ? 1'b0 : 1'bz;

    // -------------------------------------------------
    // SCL generation
    // -------------------------------------------------
    always #5 scl = ~scl;

    // -------------------------------------------------
    // I2C tasks
    // -------------------------------------------------
    task i2c_start;
        begin
            sda_drv = 0; #2;
            sda_drv = 1; #10;
        end
    endtask

    task i2c_stop;
        begin
            sda_drv = 1; #2;
            sda_drv = 0; #10;
        end
    endtask

    task i2c_write_byte(input [7:0] data);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                sda_drv = ~data[i];
                #10;
            end
            sda_drv = 0; // release for ACK
            #10;
        end
    endtask

    // -------------------------------------------------
    // Test sequence
    // -------------------------------------------------
    initial begin
        $dumpfile("i2c_slave_dummy.vcd");
        $dumpvars(0, tb_i2c_slave_dummy);

        scl = 1;
        sda_drv = 0;   // SDA idle high
        rst_n = 0;

        #20 rst_n = 1;

        i2c_start();
        i2c_write_byte({7'h48, 1'b1}); // address + READ
        #100;
        i2c_stop();

        #100 $finish;
    end

endmodule