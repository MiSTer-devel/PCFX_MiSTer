// Core testbench
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

//`define USE_IOCTL_FOR_LOAD 1

module mycore_tb;

logic		reset;
logic       CLK_50M, clk_sys, clk_ram;

initial begin
  $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
  $dumpfile("mycore_tb.vcd");
  $dumpvars();
`else
  $dumpfile("mycore_tb.verilator.fst");
  $dumpvars();
`endif
end

/////////////////////////   MEMORY   /////////////////////////

wire        SDRAM_CLK;
wire        SDRAM_CKE;
wire [12:0] SDRAM_A;
wire [1:0]  SDRAM_BA;
wire [15:0] SDRAM_DQ;
wire        SDRAM_DQML;
wire        SDRAM_DQMH;
wire        SDRAM_nCS;
wire        SDRAM_nCAS;
wire        SDRAM_nRAS;
wire        SDRAM_nWE;

sdram_xsds sdrb (.*);

//////////////////////////////////////////////////////////////////////

reg         ioctl_download = 0;
reg [7:0]   ioctl_index;
reg         ioctl_wr;
reg [24:0]  ioctl_addr;
reg [15:0]  ioctl_dout;
wire        ioctl_wait;

mycore mycore
(
	.clk_sys(clk_sys),
    .clk_cpu(CLK_50M),
    .clk_ram(clk_ram),
	.reset(reset),
    .pll_locked('1),

	.pal('0),
	.scandouble('0),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

    .SDRAM_CLK(SDRAM_CLK),
    .SDRAM_CKE(SDRAM_CKE),
    .SDRAM_A(SDRAM_A),
    .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQ(SDRAM_DQ),
    .SDRAM_DQML(SDRAM_DQML),
    .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS),
    .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nRAS(SDRAM_nRAS),
    .SDRAM_nWE(SDRAM_nWE),

	.ce_pix(),

	.HBlank(),
	.HSync(),
	.VBlank(),
	.VSync(),

	.R(),
	.G(),
	.B()
);

initial begin
    reset = 1;
    CLK_50M = 1;
    clk_sys = 1;
    clk_ram = 1;
end

initial forever begin :clkgen_50M
    #0.01 CLK_50M = ~CLK_50M; // 50 MHz
end

initial forever begin :clkgen_sys
    #0.025 clk_sys = ~clk_sys; // 20 MHz
end

initial forever begin :clkgen_ram
    #0.005 clk_ram = ~clk_ram; // 100 MHz
end

//////////////////////////////////////////////////////////////////////

string fn_rombios = "rombios.bin";
bit    swap_rombios = 1;

`ifdef USE_IOCTL_FOR_LOAD

bit         ioctl_active = 0;
bit         ioctl_swap;
integer     ioctl_fin;
bit         ioctl_wrote = 0;

always @(posedge clk_sys) if (ioctl_active) begin
integer code;
logic [15:0] data;
    if (~ioctl_download) begin
        ioctl_download <= '1;
        ioctl_addr <= 0;
    end
    else if (ioctl_wr) begin
        ioctl_wr <= '0;
        ioctl_wrote <= '1;
    end
    else if (ioctl_wrote) begin
        if (~ioctl_wait) begin
            ioctl_addr <= ioctl_addr + 25'd2;
            ioctl_wrote <= 0;
        end
    end
    else begin
        code = $fread(data, ioctl_fin, 0, 2);
        if (!$feof(ioctl_fin)) begin
            if (ioctl_swap)
                data = {data[7:0], data[15:8]};
            ioctl_dout <= data;
            ioctl_wr <= '1;
        end
        else begin
            ioctl_active <= 0;
            ioctl_download <= 0;
            ioctl_addr <= 'X;
            ioctl_dout <= 'X;
            ioctl_wr <= 0;
        end
    end
end

task ioctl_go(input string fn, bit swap_endian);
    ioctl_fin = $fopen(fn, "r");
    assert(ioctl_fin != 0) else $finish;
    ioctl_active = '1;
    ioctl_swap = swap_endian;
    while (ioctl_active)
        @(posedge clk_sys) ;
    $fclose(ioctl_fin);
endtask

task load_rombios;
    ioctl_index = {2'd0, 6'd0};
    ioctl_go(fn_rombios, swap_rombios);
endtask

`else // ifndef USE_IOCTL_FOR_LOAD

task load_file(input [24:0] base, input string fn, bit swap_endian);
integer	fin;
integer code;
logic [15:0] data;
logic [24:0] addr;
    begin
        fin = $fopen(fn, "r");
        assert(fin != 0) else $finish;
        addr = base;
        while (!$feof(fin)) begin :load_loop
            code = $fread(data, fin, 0, 2);
            if (!$feof(fin)) begin
                if (swap_endian)
                    data = {data[7:0], data[15:8]};
                sdrb.u1a.write(mycore.sdram.addr_to_bank(addr),
                               mycore.sdram.addr_to_row(addr),
                               mycore.sdram.addr_to_col(addr),
                               data);
                addr += 2;
            end
        end
        $fclose(fin);
    end
endtask

task load_rombios;
    load_file(25'h0, fn_rombios, swap_rombios);
endtask

`endif

//////////////////////////////////////////////////////////////////////

initial #0 begin
    #10 ; // wait for sdram init.

    load_rombios();
    $display("ROMs loaded.");

    reset = 0;
end

initial @(negedge reset) #(500e3) begin
    $error("Emergency exit!");
    $fatal(1);
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s mycore_tb -o mycore_tb.vvp -f mycore.files mycore_tb.sv && ./mycore_tb.vvp"
// End:
