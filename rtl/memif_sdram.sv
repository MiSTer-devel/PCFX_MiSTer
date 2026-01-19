// Use external MiSTer SDRAM as memory backing store
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module memif_sdram
  (
    input         CPU_CLK,
    input         CPU_CE,
    input         CPU_RESn,
    input         CPU_BCYSTn,

    input [19:0]  ROM_A,
    output [15:0] ROM_DO,
    input         ROM_CEn,
    output        ROM_READYn,

    input [20:0]  RAM_A,
    input [31:0]  RAM_DI,
    output [31:0] RAM_DO,
    input         RAM_CEn,
    input         RAM_WEn,
    input [3:0]   RAM_BEn,
    output        RAM_READYn,

    input [14:0]  SRAM_A,
    input [7:0]   SRAM_DI,
    output [7:0]  SRAM_DO,
    input         SRAM_CEn,
    input         SRAM_WEn,
    output        SRAM_READYn,

    input [22:0]  BMP_A,
    input [7:0]   BMP_DI,
    output [7:0]  BMP_DO,
    input         BMP_CEn,
    input         BMP_WEn,
    output        BMP_READYn,

    input         SDRAM_CLK,
    output        SDRAM_CLKREF,
    output [24:0] SDRAM_WADDR,
    output [31:0] SDRAM_DIN,
    output [3:0]  SDRAM_BE,
    output        SDRAM_WE,
    input         SDRAM_WE_RDY,
    output        SDRAM_RD,
    input         SDRAM_RD_RDY,
    output [24:0] SDRAM_RADDR,
    input [31:0]  SDRAM_DOUT
   );

localparam [24:0] ROM_BASE_A  = 25'h000_0000; // ..00F_FFFF
localparam [24:0] RAM_BASE_A  = 25'h010_0000; // ..02F_FFFF
localparam [24:0] SRAM_BASE_A = 25'h080_0000; // ..080_7FFF
localparam [24:0] BMP_BASE_A  = 25'h100_0000; // ..17F_FFFF

// SDRAM_CLK is assumed to be N * CPU_CLK, where N > 1.

// With SDRAM_CLK = 100MHz and CPU_CLK/CE = 25MHz, ROM reads take 4
// CPU cycles or 2 wait states. Coincidentally, that's the correct
// timing for PC-FX.

logic           ract = '0;
logic           wact = '0;

logic [15:0]    rom_do;
logic           rom_start_req;
logic           rom_readyn = '1;

logic [31:0]    ram_do;
logic           ram_start_req;
logic           ram_readyn = '1;

logic [7:0]     sram_do;
logic           sram_start_req;
logic           sram_readyn = '1;

logic [7:0]     bmp_do;
logic           bmp_start_req;
logic           bmp_readyn = '1;

logic           mem_start_req;
logic           mem_pend_req = '0;
logic           mem_we;
logic           mem_rdy;
logic           mem_readyn;

logic           sdram_clkref;
logic [24:0]    sdram_waddr;
logic [31:0]    sdram_din;
logic [3:0]     sdram_be;
logic           sdram_we;
logic           sdram_rd;
logic [24:0]    sdram_raddr;

logic           sdram_rd_d = '0;
logic           sdram_we_d = '0;

assign rom_start_req = ~CPU_BCYSTn & ~ROM_CEn;
assign ram_start_req = ~CPU_BCYSTn & ~RAM_CEn;
assign sram_start_req = ~CPU_BCYSTn & ~SRAM_CEn;
assign bmp_start_req = ~CPU_BCYSTn & ~BMP_CEn;
assign mem_start_req = rom_start_req | ram_start_req | sram_start_req | bmp_start_req;

assign mem_readyn = rom_readyn & ram_readyn & sram_readyn & bmp_readyn;

always @(posedge SDRAM_CLK) begin
    mem_pend_req <= (mem_pend_req | mem_start_req) & ~(ract | wact);
    sdram_rd_d <= SDRAM_RD;
    sdram_we_d <= SDRAM_WE;
end

always @(posedge SDRAM_CLK) begin
  if (~CPU_RESn) begin
      ract <= '0;
      wact <= '0;
  end
  else begin
      if (sdram_rd_d & ~SDRAM_RD)
          ract <= '1;
      else if (ract & SDRAM_RD_RDY & ~mem_readyn)
          ract <= '0;

      if (sdram_we_d & ~SDRAM_WE)
          wact <= '1;
      else if (wact & SDRAM_WE_RDY & ~mem_readyn)
          wact <= '0;
  end
end

assign mem_rdy = (ract & SDRAM_RD_RDY) | (wact & SDRAM_WE_RDY);

always @(posedge CPU_CLK) if (CPU_CE) begin
    rom_readyn <= ROM_CEn | ~mem_rdy;
    ram_readyn <= RAM_CEn | ~mem_rdy;
    sram_readyn <= SRAM_CEn | ~mem_rdy;
    bmp_readyn <= BMP_CEn | ~mem_rdy;
end

// SDRAM_DOUT is in the SDRAM_CLK domain. Latching into the CPU_CLK
// domain helps close timing.
always @(posedge CPU_CLK) if (CPU_CE) begin
    rom_do <= SDRAM_DOUT[15:0];
    ram_do <= SDRAM_DOUT[31:0];
    sram_do <= SDRAM_DOUT[(8 * SRAM_A[0])+:8];
    bmp_do <= SDRAM_DOUT[(8 * BMP_A[0])+:8];
end

assign ROM_DO = rom_do;
assign ROM_READYn = rom_readyn;

assign RAM_DO = ram_do;
assign RAM_READYn = ram_readyn;

assign SRAM_DO = sram_do;
assign SRAM_READYn = sram_readyn;

assign BMP_DO = bmp_do;
assign BMP_READYn = bmp_readyn;

always @* begin
    mem_we = '0;
    sdram_waddr = 'X;
    sdram_din = 'X;
    sdram_be = 'X;
    sdram_raddr = 'X;
    if (~ROM_CEn) begin
        sdram_raddr = ROM_BASE_A + 25'(ROM_A);
        sdram_be = '1;
    end
    else if (~RAM_CEn) begin
        mem_we = ~RAM_WEn;
        sdram_din = RAM_DI;
        sdram_be = ~RAM_BEn;
        sdram_raddr = RAM_BASE_A + 25'(RAM_A);
        sdram_waddr = sdram_raddr;
    end
    else if (~SRAM_CEn) begin
        mem_we = ~SRAM_WEn;
        sdram_din = {4{SRAM_DI}};
        sdram_be = {2'b00, SRAM_A[0], ~SRAM_A[0]};
        sdram_raddr = SRAM_BASE_A + 25'(SRAM_A);
        sdram_waddr = sdram_raddr;
    end
    else if (~BMP_CEn) begin
        mem_we = ~BMP_WEn;
        sdram_din = {4{BMP_DI}};
        sdram_be = {2'b00, BMP_A[0], ~BMP_A[0]};
        sdram_raddr = BMP_BASE_A + 25'(BMP_A);
        sdram_waddr = sdram_raddr;
    end
end

assign SDRAM_CLKREF = mem_start_req;
assign SDRAM_WADDR = sdram_waddr;
assign SDRAM_DIN = sdram_din;
assign SDRAM_BE = sdram_be;
assign SDRAM_WE = ~wact & SDRAM_WE_RDY & (mem_start_req | mem_pend_req) & mem_we;
assign SDRAM_RD = ~ract & SDRAM_RD_RDY & (mem_start_req | mem_pend_req) & ~mem_we;
assign SDRAM_RADDR = sdram_raddr;

endmodule
