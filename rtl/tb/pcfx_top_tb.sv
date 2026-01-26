// Core testbench
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

//`define USE_IOCTL_FOR_LOAD 1
`define LOAD_SRAMS 1
//`define SAVE_SRAMS 1
`define VERIFY_SRAM_LOAD 1
`define SAVE_FRAMES 1

import core_pkg::hmi_t;

module pcfx_top_tb;

logic		reset;
logic       clk_sys, clk_ram;

initial begin
    $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
    $dumpfile("pcfx_top_tb.vcd");
    $dumpvars();
`else
    $dumpfile("pcfx_top_tb.verilator.fst");
    #(3500e3) $dumpvars();
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

hmi_t       hmi;

wire        pce;
wire        hbl, vbl;
wire        vs;
wire [7:0]  r, g, b;
logic       reset_sys;

pcfx_top pcfx_top
(
	.clk_sys(clk_sys),
    .clk_ram(clk_ram),
	.reset(reset_sys),
    .pll_locked('1),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

    .bk_ena(bk_ena),
    .bk_load(bk_load),
    .bk_save(bk_save),

    .HMI(hmi),

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

    .ERROR(),

	.ce_pix(pce),

	.HBlank(hbl),
	.HSync(),
	.VBlank(vbl),
	.VSync(vs),

	.R(r),
	.G(g),
	.B(b)
);

initial begin
    reset = 1;
    clk_sys = 1;
    clk_ram = 1;

    hmi = '0;
end

initial forever begin :clkgen_sys
    #0.01 clk_sys = ~clk_sys; // 50 MHz
end

initial forever begin :clkgen_ram
    #0.005 clk_ram = ~clk_ram; // 100 MHz
end

always @(posedge clk_sys)
    reset_sys <= reset;

//////////////////////////////////////////////////////////////////////

task sdram_read(input [24:0] addr, output [15:0] d);
    sdrb.u1a.read(pcfx_top.sdram.addr_to_bank(addr),
                  pcfx_top.sdram.addr_to_row(addr),
                  pcfx_top.sdram.addr_to_col(addr),
                  d);
endtask

task sdram_write(input [24:0] addr, input [15:0] d);
    sdrb.u1a.write(pcfx_top.sdram.addr_to_bank(addr),
                   pcfx_top.sdram.addr_to_row(addr),
                   pcfx_top.sdram.addr_to_col(addr),
                   d);
endtask

//////////////////////////////////////////////////////////////////////

string fn_rombios = "rombios.bin";

`ifdef USE_IOCTL_FOR_LOAD

bit         ioctl_active = 0;
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
            data = {data[7:0], data[15:8]}; // $fread is big-endian
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

task ioctl_go(input string fn);
    ioctl_fin = $fopen(fn, "rb");
    assert(ioctl_fin != 0) else $finish;
    ioctl_active = '1;
    while (ioctl_active)
        @(posedge clk_sys) ;
    $fclose(ioctl_fin);
endtask

task load_rombios;
    ioctl_index = {2'd0, 6'd0};
    ioctl_go(fn_rombios);
endtask

`else // ifndef USE_IOCTL_FOR_LOAD

task load_file(input [24:0] base, input string fn);
integer	fin;
integer code;
logic [15:0] data;
logic [24:0] addr;
    begin
        fin = $fopen(fn, "rb");
        assert(fin != 0) else $error("Unable to open file %s", fn);
        addr = base;
        while (!$feof(fin)) begin :load_loop
            code = $fread(data, fin, 0, 2);
            if (!$feof(fin)) begin
                data = {data[7:0], data[15:8]}; // $fread is big-endian
                sdram_write(addr, data);
                addr += 2;
            end
        end
        $fclose(fin);
    end
endtask

task load_rombios;
    load_file(pcfx_top.memif_sdram.ROM_BASE_A, fn_rombios);
endtask

`endif

//////////////////////////////////////////////////////////////////////

logic [1:0]     img_mounted = 0;
logic           img_readonly = 0;
logic [63:0]    img_size = 0;
logic [31:0]    sd_lba;
logic [1:0]     sd_rd, sd_wr;
logic [1:0]     sd_ack;
logic [7:0]     sd_buff_addr = 0;
logic [15:0]    sd_buff_dout = 0;
logic [15:0]    sd_buff_din;
logic           sd_buff_wr = 0;
logic           sd_buff_rd = 0;
logic           bk_ena;
logic           bk_load = 0;
logic           bk_save = 0;

int             sd_vd;
int             sd_fin [2] = '{0, 0};
int             sd_fout [2] = '{0, 0};
longint         sd_size [2];
logic [1:0]     sd_rd_act = 0; // one-hot
logic [1:0]     sd_wr_act = 0; // one-hot
event           mount_sd, start_load_bk, start_save_bk;

assign sd_ack = sd_rd_act | sd_wr_act;

always @(posedge clk_sys) begin
integer vd;
integer code;
logic [15:0] data;

    if (~|sd_rd_act & |sd_rd) begin
        vd = $clog2(sd_rd);
        sd_rd_act[vd] <= 1;
        sd_buff_addr <= 0;
        code = $fseek(sd_fin[vd], sd_lba * 512, 0);
        assert(code == 0) else $error("Unable to seek");
    end
    else if (~|sd_wr_act & |sd_wr) begin
        vd = $clog2(sd_wr);
        sd_wr_act[vd] <= 1;
        sd_buff_addr <= 0;
        code = $fseek(sd_fout[vd], sd_lba * 512, 0);
        assert(code == 0) else $error("Unable to seek");
    end
    else if (|sd_rd_act) begin
        vd = $clog2(sd_rd_act);
        if (~sd_buff_wr) begin
            if ($feof(sd_fin[vd]))
                data = '0;
            else
                $fread(data, sd_fin[vd], 0, 2);
            sd_buff_dout <= {data[7:0], data[15:8]}; // $fread is big-endian
            sd_buff_wr <= 1;
        end
        else begin
            sd_buff_wr <= 0;
            if (&sd_buff_addr) begin
                sd_rd_act[vd] <= 0;
            end
            sd_buff_addr <= sd_buff_addr + 1'd1;
        end
    end
    else if (|sd_wr_act) begin
        vd = $clog2(sd_wr_act);
        if (sd_buff_rd) begin
            $fwrite(sd_fout[vd], "%c%c", sd_buff_din[7:0], sd_buff_din[15:8]);
            if (&sd_buff_addr) begin
                sd_wr_act[vd] <= 0;
            end
            sd_buff_addr <= sd_buff_addr + 1'd1;
        end
        sd_buff_rd <= ~sd_buff_rd;
    end
end

always @mount_sd begin
    img_size <= sd_size[sd_vd];
    @(posedge clk_sys) ;
    img_mounted[sd_vd] <= '1;
    @(posedge clk_sys) ;
    img_mounted <= '0;
end

always @start_load_bk begin
    @(posedge clk_sys) bk_load <= '1;
    while (~pcfx_top.bk_loading)
        @(posedge clk_sys) ;
    @(posedge clk_sys) bk_load <= '0;
end

always @start_save_bk begin
    @(posedge clk_sys) bk_save <= '1;
    while (~pcfx_top.bk_saving)
        @(posedge clk_sys) ;
    @(posedge clk_sys) bk_save <= '0;
end

task mount_sd_file(string fn, int vd);
string fnin, fnout;
integer	fin, fout;
integer code;
    fnin = {fn, ".bin"};
    fnout = {fn, ".out.bin"};
    fin = $fopen(fnin, "rb");
    fout = $fopen(fnout, "wb");
    if (fin == 0)
        $warning("Unable to open file %s", fnin);
    else if (fout == 0)
        $warning("Unable to open file %s for write", fnout);
    else begin
        sd_fin[vd] = fin;
        sd_fout[vd] = fout;
        code = $fseek(fin, 0, 2);
        sd_size[vd] = $ftell(fin);
        sd_vd = vd;
        -> mount_sd;
        repeat (3) @(posedge clk_sys) ; // wait for mount completion
    end
endtask

task mount_sram;
    mount_sd_file("sram", 0);
endtask

task mount_bmp;
    mount_sd_file("bmp", 1);
endtask

task load_bk;
    -> start_load_bk;
    while (~bk_load)
        @(posedge clk_sys) ;
    @(posedge clk_sys) ;
    while (pcfx_top.bk_loading)
        @(posedge clk_sys) ;

`ifdef VERIFY_SRAM_LOAD
    verify_bk_load(0);
    verify_bk_load(1);
`endif
endtask

task verify_bk_load(int vd);
bit [15:0] dfile, dram;
bit [24:0] base, addr;
    if (sd_size[vd] == 0)
        return;
    $display("Verifying SD vol %1d", vd);
    base = (vd != 0) ? pcfx_top.memif_sdram.BMP_BASE_A : pcfx_top.memif_sdram.SRAM_BASE_A;
    addr = 0;
    $fseek(sd_fin[vd], 0, 0);
    for (longint i = 0; i < sd_size[vd]; i++) begin
        $fread(dfile, sd_fin[vd], 0, 2);
        dfile = {dfile[7:0], dfile[15:8]}; // $fread is big-endian
        sdram_read(base + addr, dram);
        assert(dfile == dram) else $error("Wanted %x, got %x @ addr. %x", dfile, dram, addr);
        addr += 25'd2;
    end
endtask

task save_bk;
    -> start_save_bk;
    while (~bk_save)
        @(posedge clk_sys) ;
    @(posedge clk_sys) ;
    while (pcfx_top.bk_saving)
        @(posedge clk_sys) ;
endtask

//////////////////////////////////////////////////////////////////////

`ifdef SAVE_FRAMES

integer frame = 0;
integer fpic;
logic   pice;
string  fname;

initial fpic = -1;
always @(negedge vs) begin
  if (fpic != -1) begin
    $fclose(fpic);
    fpic = -1;
`ifdef VERILATOR
    $system({"python3 render2png.py ", fname, {".hex "}, fname, ".png; rm ", fname, ".hex"});
`endif
  end
  $display("%t: Frame %03d  A=%x", $time, frame, pcfx_top.mach.cpu_a);
  $sformat(fname, "frames/render-%03d", frame);
  pice = 0;
  if (frame >= 220) begin
    fpic = $fopen({fname, ".hex"}, "w");
  end
  frame = frame + 1;
end
final
  $fclose(fpic);

wire de = ~(hbl | vbl);

always @(posedge clk_sys) begin
  if (fpic != -1 && pce) begin
    if (de) begin
      $fwrite(fpic, "%x", {r, g, b});
      pice = 1;
    end
    else if (pice) begin
      pice = 0;
      $fwrite(fpic, "\n");
    end
  end
end

`endif

//////////////////////////////////////////////////////////////////////

event running;

initial #0 begin
    #10 ; // wait for sdram init.

    load_rombios();
    $display("ROM loaded.");

    //load_file(pcfx_top.memif_sdram.RAM_BASE_A, "ram.bin", '0);

    reset = 0;
    $display("Reset released.");

`ifdef LOAD_SRAMS
    mount_sram();
    mount_bmp();
    if (bk_ena) begin
        load_bk();
        $display("RAMs loaded.");
    end
`endif

    -> running;
end

initial begin
    @(running) ;
    repeat (4) #(1000e3) ;
    //#(500e3) ;

`ifdef SAVE_SRAMS
    if (bk_ena) begin
        save_bk();
        $display("RAMs saved.");
    end
`endif

    //$writememh("sdram.hex", sdrb.u1a.mem);
    //$writememh("vram0.hex", pcfx_top.mach.vram0.mem);
    //$writememh("vram1.hex", pcfx_top.mach.vram1.mem);
    //$writememh("vce_cp.hex", pcfx_top.mach.vce.cpram.mem);

    $finish;
end

initial if (1) begin
    @(running) ;
    #(216e3);

    repeat (4) begin
        $display("Pressing JP1.Select...");
        hmi.jp1.select = '1;
        #(20e3) hmi.jp1.select = '0;
        #(20e3) ;
    end

    $display("Pressing JP1.Run...");
    hmi.jp1.run = '1;
    #(20e3) hmi.jp1.run = '0;
    #(20e3);
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s pcfx_top_tb -o pcfx_top_tb.vvp -f pcfx_top.files pcfx_top_tb.sv && ./pcfx_top_tb.vvp"
// End:
