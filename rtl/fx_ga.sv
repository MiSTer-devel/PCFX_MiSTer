// PC-FX Gate Array
//
// Implement enough of the chip to appease the BIOS.
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module fx_ga
  (
   input         RESn,
   input         CLK,
   input         CE,

   // CPU Memory / I/O bus interface
   input [31:0]  A,
   input [15:0]  DI,
   output [15:0] DO,
   input [3:0]   BEn,
   input [1:0]   ST,
   input         DAn,
   input         MRQn,
   input         RW,
   input         BCYSTn,
   output        READYn,
   output        SZRQn,

   // Address decoder
   output        A1_16,
   output        ROM_CEn,
   output        RAM_CEn,
   output        SRAM_CEn,
   output        BMP_CEn,
   output        IO_CEn,

   output        FX_GA_CSn,
   output        PSG_CSn,
   output        VPU_CSn,
   output        VCE_CSn,
   output        VDC0_CSn,
   output        VDC1_CSn,
   output        MMC_CSn,

   // Memory control
   input         ROM_READYn,
   input         RAM_READYn,
   input         SRAM_READYn,
   input         BMP_READYn,

   // Device control
   output        WRn,
   output        RDn,
   output        VDC_CPU_CE,
   input         VDC0_BUSYn,
   input         VDC1_BUSYn,
   input         MMC_BUSYn,

   // Device interrupts
   input [3:0]   DINT,

   // CPU interrupt interface
   output        CINT,
   output [3:0]  CINTVn,
   output        CNMIn,

   // K-port interface
   output [1:0]  KP_LATCH,
   output [1:0]  KP_CLK,
   output [1:0]  KP_RW,
   input [1:0]   KP_DIN,
   output [1:0]  KP_DOUT
   );

//////////////////////////////////////////////////////////////////////
// Memory / I/O bus interface

logic           unk_cen;
logic           io_readyn;

assign READYn = unk_cen & ROM_READYn & RAM_READYn & SRAM_READYn & BMP_READYn & io_readyn;
assign SZRQn = ~unk_cen | (ROM_CEn & IO_CEn & SRAM_CEn & BMP_CEn);

//////////////////////////////////////////////////////////////////////
// Address decoder

// Assert A[1] for upper-halfword or -byte access to 16-bit memory /
// IO, i.e., if one or both of BEn[3:2] are asserted.
assign A1_16 = A[1] | (~&BEn[3:2] & &BEn[1:0]);

assign ROM_CEn  = ~(~MRQn & (A[31:28] == 4'hF));      // F000_0000 .. FFFF_FFFF
assign RAM_CEn  = ~(~MRQn & (A[31:24] == 8'h00));     // 0000_0000 .. 00FF_FFFF
assign SRAM_CEn = ~(~MRQn & (A[31:27] == 5'b1110_0)); // E000_0000 .. E7FF_FFFF
assign BMP_CEn  = ~(~MRQn & (A[31:27] == 5'b1110_1)); // E800_0000 .. EFFF_FFFF
assign IO_CEn   = ~((MRQn | (A[31:28] == 4'h8)) & (~BCYSTn | ~DAn)
                    & (ST == 2'b10));
assign unk_cen = ~(RAM_CEn & ROM_CEn & SRAM_CEn & BMP_CEn & IO_CEn);

assign FX_GA_CSn = ~(~IO_CEn & (A[30:12] == 19'h00000)) |
                   ~(PSG_CSn & VPU_CSn & VCE_CSn & VDC0_CSn &
                     VDC1_CSn & MMC_CSn);

assign PSG_CSn  = ~(~IO_CEn & (A[27:8] == 20'h00001)); // HuC6230
assign VPU_CSn  = ~(~IO_CEn & (A[27:8] == 20'h00002)); // HuC6271
assign VCE_CSn  = ~(~IO_CEn & (A[27:8] == 20'h00003)); // HuC6261
assign VDC0_CSn = ~(~IO_CEn & (A[27:8] == 20'h00004)); // HuC6270 #0
assign VDC1_CSn = ~(~IO_CEn & (A[27:8] == 20'h00005)); // HuC6270 #1
assign MMC_CSn  = ~(~IO_CEn & (A[27:8] == 20'h00006)); // HuC6272

//////////////////////////////////////////////////////////////////////
// I/O device control

logic           io_wait;
logic [2:0]     io_wait_cnt;
logic           vdc_busy_end;

assign WRn = IO_CEn | vdc_busy_end | DAn | RW;
assign RDn = IO_CEn | vdc_busy_end | DAn | ~RW;

// FXGABOAD says: "Write access to normal I/O requires six cycles," or
// 4 wait states.  Assume that read access does, too.
//
// TODO: Implement Huc* write buffer.

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        io_wait_cnt <= '0;
    end
    else begin
        if (io_wait)            // I/O cycle in progress
            io_wait_cnt <= io_wait_cnt - 1'd1;
        else if (~IO_CEn & ~BCYSTn) // New I/O cycle start
            io_wait_cnt <= 3'd4;
    end
end

assign io_wait = |io_wait_cnt;

always @* begin
    if (~VDC0_CSn)              io_readyn = ~VDC0_BUSYn;
    else if (~VDC1_CSn)         io_readyn = ~VDC1_BUSYn;
    else if (~MMC_CSn)          io_readyn = ~MMC_BUSYn;
    else                        io_readyn = IO_CEn;

    io_readyn |= io_wait;
end

// huc6270.vhd inputs a signal that never existed in actual hardware:
// the internal clock enable of the CPU.  It uses this to determine
// when the I/O bus cycle completes.  (Actual HW would instead use the
// de-assertion of RDn / WRn for this purpose.)
assign VDC_CPU_CE = CE & ~io_readyn;

// huc6270.vhd assumes that, when it de-asserts BUSYn, RDn / WRn will
// de-assert in the next clock cycle, regardless of CE.  But, CPU will
// only act on BUSYn and then change RDn / WRn on CE.  This workaround
// de-asserts RDn / WRn early, then resets when DAn de-asserts (CPU
// ends bus cycle).
wire vdc_busy = ~io_wait & (~VDC0_BUSYn | ~VDC1_BUSYn);
logic vdc_busy_d;
always @(posedge CLK) begin
    vdc_busy_d <= vdc_busy;
    vdc_busy_end <= (vdc_busy_end | (vdc_busy_d & ~vdc_busy)) & ~(~RESn | DAn);
end


//////////////////////////////////////////////////////////////////////
// Register interface

logic [6:0]     isr;
logic [6:0]     imr;
logic [2:0]     ilr [7];

logic [15:0]    dout;

logic [15:0]    kpc0_do, kpc1_do;
logic           kpc0_csn, kpc1_csn;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        imr <= '1;
        ilr[0] <= 3'd7;
        ilr[1] <= 3'd6;
        ilr[2] <= 3'd5;
        ilr[3] <= 3'd4;
        ilr[4] <= 3'd7;
        ilr[5] <= 3'd6;
        ilr[6] <= 3'd5;
    end
    else if (~FX_GA_CSn & ~WRn) begin
        case (A[11:4])
            8'hE4: imr <= DI[6:0];
            8'hE8: {ilr[3], ilr[2], ilr[1], ilr[0]} <= DI[11:0];
            8'hEC: {ilr[6], ilr[5], ilr[4]} <= DI[8:0];
            default: ;
        endcase
    end
end

always @* begin
    dout = '0;
    if (~FX_GA_CSn & ~RDn) begin
        if (~kpc0_csn)
            dout = kpc0_do;
        else if (~kpc1_csn)
            dout = kpc1_do;
        else
            case (A[11:4])
                8'hE0: dout[6:0] = isr;
                8'hE4: dout[6:0] = imr;
                8'hE8: dout[11:0] = {ilr[3], ilr[2], ilr[1], ilr[0]};
                8'hEC: dout[8:0] = {ilr[6], ilr[5], ilr[4]};
                default: ;
            endcase
    end
end

assign DO = dout;


//////////////////////////////////////////////////////////////////////
// TMC: Timer Control Unit
// (TODO)

//////////////////////////////////////////////////////////////////////
// KPC: K-Port (Keypad) Control Unit

logic           kpc0_int, kpc1_int, kpc_int;

assign kpc0_csn = ~(~FX_GA_CSn & (A[11:7] == 5'h00)); // 000 .. 07F
assign kpc1_csn = ~(~FX_GA_CSn & (A[11:7] == 5'h01)); // 080 .. 0FF

fx_ga_kpc kpc0
   (
    .RESn(RESn),
    .CLK(CLK),
    .CE(CE),

    .A6(A[6]),
    .A1(A1_16),
    .CSn(kpc0_csn),
    .RDn(RDn),
    .WRn(WRn),
    .DI(DI),
    .DO(kpc0_do),

    .INT(kpc0_int),

    .KP_LATCH(KP_LATCH[0]),
    .KP_CLK(KP_CLK[0]),
    .KP_RW(KP_RW[0]),
    .KP_DIN(KP_DIN[0]),
    .KP_DOUT(KP_DOUT[0])
    );

fx_ga_kpc kpc1
   (
    .RESn(RESn),
    .CLK(CLK),
    .CE(CE),

    .A6(A[6]),
    .A1(A1_16),
    .CSn(kpc1_csn),
    .RDn(RDn),
    .WRn(WRn),
    .DI(DI),
    .DO(kpc1_do),

    .INT(kpc1_int),

    .KP_LATCH(KP_LATCH[1]),
    .KP_CLK(KP_CLK[1]),
    .KP_RW(KP_RW[1]),
    .KP_DIN(KP_DIN[1]),
    .KP_DOUT(KP_DOUT[1])
    );

assign kpc_int = kpc0_int | kpc1_int;

//////////////////////////////////////////////////////////////////////
// ITC: Interrupt Control Unit
//
// TODO:
// - AERR Address Error
// - Internal interrupt sources: INTEX (5), INTTM (6)

logic [6:0]     eisr;           // un-masked (enabled) ISR
logic [2:0]     hail;           // highest active interrupt level

assign isr[6:5] = '0;
assign isr[4] = kpc_int;
assign isr[3:0] = DINT[3:0];

assign eisr = isr & ~imr;

// Identify the highest level in the set of enabled active interrupts.
always @* begin
    hail = '0;
    for (int i = 0; i <= 6; i++) begin :scan_int
        if (eisr[i] & (ilr[i] > hail))
            hail = ilr[i];
    end
end

assign CINT = |eisr;
assign CINTVn = {1'b0, ~hail};
assign CNMIn = '1;

endmodule

`include "fx_ga_kpc.sv"
