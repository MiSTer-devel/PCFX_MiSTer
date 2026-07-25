// Core testbench
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

//`define USE_IOCTL_FOR_LOAD_ROMBIOS 1
//`define LOAD_BMP_ROM 1
`define LOAD_SRAMS 1
//`define SAVE_SRAMS 1
`define VERIFY_SRAM_LOAD 1
`define SAVE_FRAMES 1

`ifdef PCFX_TOP_TB_CD
import "DPI-C" function bit pcfx_mount_cd();
import "DPI-C" task pcfx_read_cd(bit [7:0] buffer [], input int lba,
                                 input int cnt);
`endif

import core_pkg::hmi_t;

module pcfx_top_tb;

logic		reset = 1;
logic       clk_sys = 1;
logic       clk_ram = 1;

initial begin
    $timeformat(-6, 0, " us", 1);

`ifndef VERILATOR
    //$dumpfile("pcfx_top_tb.vcd");
    $dumpvars();
`else
    $dumpfile("pcfx_top_tb.verilator.fst");
    repeat (6) #(1000e3) ;
    #(289e3) ;
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

localparam CLK_RAM_MHZ = 100.0;
assign SDRAM_CLK = clk_ram;

sdram_xsds #(.CLK_MHZ(CLK_RAM_MHZ)) sdrb (.*);

//////////////////////////////////////////////////////////////////////

logic [2:0] img_mounted = 0;
logic       img_readonly = 0;
logic [63:0] img_size = 0;

logic [31:0] sd_lba_bk, sd_lba_cd;
logic [5:0]  sd_blk_cnt_bk, sd_blk_cnt_cd;
logic [2:0]  sd_rd, sd_wr;
logic [2:0]  sd_ack;

logic [12:0] sd_buff_addr = 0;
logic [15:0] sd_buff_dout = 0;
logic [15:0] sd_buff_din_bk;
logic        sd_buff_wr = 0;

reg         ioctl_download = 0;
reg [7:0]   ioctl_index;
reg         ioctl_wr;
reg [24:0]  ioctl_addr = 0;
reg [15:0]  ioctl_dout;
wire        ioctl_wait;

logic [1:0] bk_ena_img_mount;
logic       bk_ena;
logic       bk_load = 0;
logic       bk_save = 0;
logic       bmp_eject_rom = 0;

hmi_t       hmi = '0;

wire        pce;
wire        hbl, vbl;
wire        vs;
wire [7:0]  r, g, b;
logic       reset_sys;

pcfx_top #(.CLK_RAM_MHZ(CLK_RAM_MHZ)) pcfx_top
(
	.clk_sys(clk_sys),
    .clk_ram(clk_ram),
	.reset(reset_sys),
    .pll_locked('1),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.sd_lba_bk(sd_lba_bk),
	.sd_lba_cd(sd_lba_cd),
    .sd_blk_cnt_bk(sd_blk_cnt_bk),
    .sd_blk_cnt_cd(sd_blk_cnt_cd),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din_bk(sd_buff_din_bk),
	.sd_buff_wr(sd_buff_wr),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

    .bk_ena_img_mount(bk_ena_img_mount),
    .bk_ena(bk_ena),
    .bk_load(bk_load),
    .bk_save(bk_save),
    .bmp_rom_inserted(),
    .bmp_eject_rom(bmp_eject_rom),

    .HMI(hmi),

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
	.B(b),

    .AUD_SLOUT(),
    .AUD_SROUT()
);

initial forever begin :clkgen_sys
    #0.01 clk_sys = ~clk_sys; // 50 MHz
end

initial forever begin :clkgen_ram
    #0.005 clk_ram = ~clk_ram; // 100 MHz
end

initial reset_sys = 1;
always @(posedge clk_sys)
    reset_sys <= reset;

//////////////////////////////////////////////////////////////////////

task sdram_read(input [26:0] addr, output [15:0] d);
    sdrb.u1a.read(pcfx_top.sdram.addr_to_bank(addr),
                  pcfx_top.sdram.addr_to_row(addr),
                  pcfx_top.sdram.addr_to_col(addr),
                  d);
endtask

task sdram_write(input [26:0] addr, input [15:0] d);
    sdrb.u1a.write(pcfx_top.sdram.addr_to_bank(addr),
                   pcfx_top.sdram.addr_to_row(addr),
                   pcfx_top.sdram.addr_to_col(addr),
                   d);
endtask

//////////////////////////////////////////////////////////////////////

string fn_rombios = "rombios.bin";
string fn_bmp_rom = "rom.fxb";

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
            ioctl_dout <= 'X;
            ioctl_wr <= 0;
        end
    end
end

task ioctl_go(input string fn);
    ioctl_fin = $fopen(fn, "rb");
    assert(ioctl_fin != 0) else $finish;
    $display("Loading ROM %s via ioctl", fn);
    ioctl_active = '1;
    while (ioctl_active)
        @(posedge clk_sys) ;
    @(posedge clk_sys) ;
    $fclose(ioctl_fin);
endtask

`ifdef USE_IOCTL_FOR_LOAD_ROMBIOS
task load_rombios;
    ioctl_index = {2'd0, 6'd0};
    ioctl_go(fn_rombios);
endtask
`endif

task load_bmp_rom;
    ioctl_index = {2'd0, 6'd2};
    ioctl_go(fn_bmp_rom);
endtask

//////////////////////////////////////////////////////////////////////

task load_file(input [26:0] base, input string fn);
integer	fin;
integer code;
logic [15:0] data;
logic [26:0] addr;
    begin
        fin = $fopen(fn, "rb");
        assert(fin != 0) else $error("Unable to open file %s", fn);
        $display("Loading ROM %s directly", fn);
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

`ifndef USE_IOCTL_FOR_LOAD_ROMBIOS
task load_rombios;
    load_file(pcfx_top.memif_sdram.ROM_BASE_A, fn_rombios);
endtask
`endif

//////////////////////////////////////////////////////////////////////

`ifdef PCFX_TOP_TB_CD

localparam CDI_SECTOR_LEN = 2352;
localparam CDI_SUBCHANNEL_LEN = ((12+96)*2);
localparam CDI_CDIC_BUFFER_SIZE = (CDI_SECTOR_LEN + CDI_SUBCHANNEL_LEN);

bit [7:0]       cd_rbuf [CDI_CDIC_BUFFER_SIZE];
event           mount_cd;

task load_cd;
bit mounted;
    mounted = pcfx_mount_cd();
    if (mounted) begin
        -> mount_cd;
        repeat (3) @(posedge clk_sys) ; // wait for mount completion
        $display("CD loaded.");
    end
endtask

always @mount_cd begin
    img_size <= 64'd407024064;
    @(posedge clk_sys) ;
    img_mounted[2] <= '1;
    @(posedge clk_sys) ;
    img_mounted <= '0;
end

task read_cd(input int lba);
    pcfx_read_cd(cd_rbuf, lba, 1);
endtask

task get_cd_rbuf(input int off, output [15:0] data, output last);
    data = '0;
    last = off == CDI_CDIC_BUFFER_SIZE/2-1;
    if (off*2 < CDI_CDIC_BUFFER_SIZE) begin
        data[0+:8] = cd_rbuf[off*2+0];
        data[8+:8] = cd_rbuf[off*2+1];
    end
endtask

`endif

//////////////////////////////////////////////////////////////////////

localparam BKN = 2;

logic           sd_buff_rd = 0;

int             sd_vd;
int             sd_fin [BKN] = '{0, 0};
int             sd_fout [BKN] = '{0, 0};
longint         sd_size [BKN];
logic [2:0]     sd_rd_act = 0; // one-hot
logic [2:0]     sd_wr_act = 0; // one-hot
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
        if (vd < BKN) begin
            assert(sd_blk_cnt_bk == '0);
            code = $fseek(sd_fin[vd], sd_lba_bk * 512, 0);
            assert(code == 0) else $error("Unable to seek");
        end
        else begin
`ifdef PCFX_TOP_TB_CD
            assert(sd_blk_cnt_cd >= 6'(8-1));
            read_cd(sd_lba_cd);
`endif
        end
    end
    else if (~|sd_wr_act & |sd_wr) begin
        vd = $clog2(sd_wr);
        sd_wr_act[vd] <= 1;
        sd_buff_addr <= 0;
        if (vd < BKN) begin
            assert(sd_blk_cnt_bk == '0);
            code = $fseek(sd_fout[vd], sd_lba_bk * 512, 0);
            assert(code == 0) else $error("Unable to seek");
        end
    end
    else if (|sd_rd_act) begin
        vd = $clog2(sd_rd_act);
        if (vd < BKN) begin
            if (~sd_buff_wr) begin
                if ($feof(sd_fin[vd]))
                    data = '0;
                else
                    code = $fread(data, sd_fin[vd], 0, 2);
                sd_buff_dout <= {data[7:0], data[15:8]}; // $fread is big-endian
                sd_buff_wr <= 1;
            end
            else begin
                sd_buff_wr <= 0;
                if (&sd_buff_addr[7:0]) begin
                    sd_rd_act[vd] <= 0;
                end
                sd_buff_addr <= sd_buff_addr + 1'd1;
            end
        end
        else begin
        static bit last;
`ifdef PCFX_TOP_TB_CD
            if (~sd_buff_wr) begin
                get_cd_rbuf(int'(sd_buff_addr), data, last);
                sd_buff_dout <= data;
                sd_buff_wr <= 1;
            end
            else begin
                sd_buff_wr <= 0;
                if (last)
                    sd_rd_act[vd] <= 0;
                sd_buff_addr <= sd_buff_addr + 1'd1;
            end
`endif
        end
    end
    else if (|sd_wr_act) begin
        vd = $clog2(sd_wr_act);
        if (vd < BKN) begin
            if (sd_buff_rd) begin
                $fwrite(sd_fout[vd], "%c%c", sd_buff_din_bk[7:0], sd_buff_din_bk[15:8]);
                if (&sd_buff_addr[7:0]) begin
                    sd_wr_act[vd] <= 0;
                end
                sd_buff_addr <= sd_buff_addr + 1'd1;
            end
            sd_buff_rd <= ~sd_buff_rd;
        end
        else begin
            // No writes to CD
            sd_wr_act[vd] <= 0;
        end
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
    if (~bk_ena_img_mount[vd])
        return;
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
bit [26:0] base, addr;
integer code;
    if (sd_size[vd] == 0)
        return;
    $display("Verifying SD vol %1d", vd);
    base = (vd != 0) ? pcfx_top.memif_sdram.BMP_BASE_A : pcfx_top.memif_sdram.SRAM_BASE_A;
    addr = 0;
    code = $fseek(sd_fin[vd], 0, 0);
    for (longint i = 0; i < sd_size[vd]; i++) begin
        code = $fread(dfile, sd_fin[vd], 0, 2);
        dfile = {dfile[7:0], dfile[15:8]}; // $fread is big-endian
        sdram_read(base + addr, dram);
        assert(dfile == dram) else $error("Wanted %x, got %x @ addr. %x", dfile, dram, addr);
        addr += 27'd2;
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
  if (frame >= 0) begin
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

`else
integer frame = 0;
always @(negedge vs) begin
  $display("%t: Frame %03d  A=%x", $time, frame, pcfx_top.mach.cpu_a);
  frame = frame + 1;
end
`endif

//////////////////////////////////////////////////////////////////////

event running;

initial #0 begin
    #150 ; // wait for sdram init.

    load_rombios();
`ifdef LOAD_BMP_ROM
    load_bmp_rom();
`endif
    $display("ROM(s) loaded.");

    //load_file(pcfx_top.memif_sdram.RAM_BASE_A, "ram.bin", '0);

`ifdef PCFX_TOP_TB_CD
    load_cd();
`endif

    reset = 0;
    $display("Reset released.");

    // Skip loading CD, resume at entry point
    $readmemh("sdram_cd.hex", sdrb.u1a.mem);
    force pcfx_top.mach.cpu.inex.ha = 32'h00008000;
    while (pcfx_top.mach.cpu_a != 32'h00008000)
        @(posedge clk_sys) ;
    $display("Booted.");
    release pcfx_top.mach.cpu.inex.ha;

    // RTZ: Skip the startup splash screens: replace "JAL 000141CE" with NOPs
    sdram_write(pcfx_top.memif_sdram.RAM_BASE_A + 27'h00013ce2, 0);
    sdram_write(pcfx_top.memif_sdram.RAM_BASE_A + 27'h00013ce4, 0);

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
    
    repeat (6) #(1000e3) ;
    #(335e3) ;

`ifdef SAVE_SRAMS
    if (bk_ena) begin
        save_bk();
        $display("RAMs saved.");
    end
`endif

    //$writememh("sdram.hex", sdrb.u1a.mem);
    //$writememh("vram0.hex", pcfx_top.mach.vram0.mem);
    //$writememh("vram1.hex", pcfx_top.mach.vram1.mem);
    $writememh("vce_cp.hex", pcfx_top.mach.vce.cpram.mem);
    pcfx_top.mach.vce.dump_regs();
    pcfx_top.mach.mmc.dump_regs();

    $finish;
end

initial if (1) begin
    @(running) ;
    repeat (6) #(1000e3) ;
    #(292e3) ;

    $display("Pressing JP1.B1....");
    hmi.jp1.b[1] = '1;
    #(20e3) hmi.jp1.b[1] = '0;
    #(20e3);
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s pcfx_top_tb -o pcfx_top_tb.vvp -f pcfx_top.files pcfx_top_tb.sv && ./pcfx_top_tb.vvp"
// End:
