// KPC (K-Port (Keypad) Control Unit) testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module kpc_tb;

logic		reset;
logic       clk, ce;

initial begin
    $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
    $dumpfile("kpc_tb.vcd");
    $dumpvars();
`else
    $dumpfile("kpc_tb.verilator.fst");
    #418116 $dumpvars();
`endif
end

logic [6:0]     a;
logic           csn, rdn, wrn;
logic [15:0]    din, dout;
logic           dut_int;
logic           kp_latch, kp_clk, kp_rw, kp_din, kp_dout;
logic [31:0]    kp_data_next, kp_data_sr;
logic           kp_dout_latched;

fx_ga_kpc dut
(
    .RESn(~reset),
    .CLK(clk),
    .CE(ce),

    .A6(a[6]),
    .A1(a[1]),
    .CSn(csn),
    .RDn(rdn),
    .WRn(wrn),
    .DI(din),
    .DO(dout),

    .INT(dut_int),

    .KP_LATCH(kp_latch),
    .KP_CLK(kp_clk),
    .KP_RW(kp_rw),
    .KP_DIN(kp_din),
    .KP_DOUT(kp_dout)
);

initial begin
    reset = 1;
    ce = 0;
    clk = 1;
    rdn = 1;
    wrn = 1;
    csn = 1;
end

initial forever begin :ckgen
    #0.01 clk = ~clk; // 50 MHz
end

always @(posedge clk) begin :cegen
    ce <= ~ce;
end

always @(posedge kp_latch) begin
    kp_data_sr <= kp_data_next;
end

always @(posedge kp_clk) begin
    kp_data_sr <= {kp_dout_latched, kp_data_sr[31:1]};
end

always @(negedge kp_clk) begin
    kp_dout_latched <= ~kp_dout;
end

assign kp_din = kp_rw | ~kp_data_sr[0];

//////////////////////////////////////////////////////////////////////

task reg_write(input [6:0] rs, input [15:0] v);
    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    a <= rs;
    din <= v;
    wrn <= 0;
    csn <= 0;

    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    din <= 'X;
    wrn <= 1;
    csn <= 1;
endtask

task reg_read(input [6:0] rs, input [15:0] v);
    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    a <= rs;
    rdn <= 0;
    csn <= 0;

    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    rdn <= 1;
    csn <= 1;

    assert(dout == v);
endtask

task init_kp_data(input [31:0] v);
    kp_dout_latched = '0;
    kp_data_sr = '0;
    kp_data_next = v;
endtask

//////////////////////////////////////////////////////////////////////

task test_initial;
    reg_read(7'h00, {12'b0, 4'b0110});
    reg_read(7'h40, 16'b0);
    reg_read(7'h42, 16'b0);
endtask

// Output: System -> Controller
task test_kp_output(input [31:0] data);
    init_kp_data('0);
    assert(~dut_int);
    reg_write(7'h40, data[15:0]);
    reg_write(7'h42, data[31:16]);
    reg_write(7'h00, {12'b0, 4'b0001});
    reg_read(7'h00, {12'b0, 4'b0001});
    assert(~dut_int);
    assert(kp_rw == '1);
    #43 reg_read(7'h00, {12'b0, 4'b0001});
    assert(~dut_int);
    #43 reg_read(7'h00, {12'b0, 4'b1000});
    assert(dut_int);
    #2 reg_read(7'h40, data[15:0]); // clear END
    @(posedge clk) assert(~dut_int);
    reg_read(7'h42, data[31:16]);
    assert(kp_data_sr == data);
    reg_read(7'h00, {12'b0, 4'b0000});
    #20 ;
endtask

// Input: Controller -> System
task test_kp_input(input [31:0] data);
    init_kp_data(data);
    assert(~dut_int);
    reg_write(7'h00, {12'b0, 4'b0101});
    reg_read(7'h00, {12'b0, 4'b0101});
    assert(~dut_int);
    assert(kp_rw == '0);
    #43 reg_read(7'h00, {12'b0, 4'b0101});
    assert(~dut_int);
    #43 reg_read(7'h00, {12'b0, 4'b1100});
    assert(dut_int);
    #2 reg_read(7'h40, data[15:0]);
    @(posedge clk) assert(~dut_int);
    reg_read(7'h42, data[31:16]);
    reg_read(7'h00, {12'b0, 4'b0100});
    #20 ;
endtask

initial #0 begin
    init_kp_data('0);

    #10 @(posedge clk) reset <= 0;
    #11 @(posedge clk) ;

    test_initial();

    test_kp_output(32'h50FAAF05);
    test_kp_output(32'hAF0550FA);
    test_kp_output(32'hCDEF1234);

    test_kp_input(32'h50FAAF05);
    test_kp_input(32'hAF0550FA);
    test_kp_input(32'h1234CDEF);

    reg_write(7'h00, {12'b0, 4'b0000});

    $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s kpc_tb -o kpc_tb.vvp ../fx_ga_kpc.sv kpc_tb.sv && ./kpc_tb.vvp"
// End:
