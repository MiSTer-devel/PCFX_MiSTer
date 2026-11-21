// PC-FX Gate Array
//
// Implement enough of the chip to appease the BIOS.
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// Notes:
//
// All HuC* I/O device memory (register) access -- data and control
// buses -- is routed through this module.

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

   // CPU bus address decoder
   output        A1_16,
   output        ROM_CEn,
   output        RAM_CEn,
   output        SRAM_CEn,
   output        MCP_CSn,
   output        FX_GA_CSn,

   // Memory control
   input         ROM_READYn,
   input         RAM_READYn,
   input         SRAM_READYn,
   input         MCP_READYn,

   // I/O device memory bus interface
   output [5:1]  IO_A,
   input [15:0]  IO_DI,
   output [15:0] IO_DO,
   output        IO_WRn,
   output        IO_RDn,

   // I/O device address decoder
   output        APU_CSn,
   output        VPU_CSn,
   output        VCE_CSn,
   output        VDC0_CSn,
   output        VDC1_CSn,
   output        MMC_CSn,

   // Device control
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
// CPU Memory / I/O bus interface

logic           unk_cen;
logic           fx_ga_readyn, io_busy, io_readyn;
logic           vdc_busy_end;
logic           cpu_wrn, cpu_rdn;

assign READYn = unk_cen & ROM_READYn & RAM_READYn & SRAM_READYn & MCP_READYn & fx_ga_readyn;
assign SZRQn = ~unk_cen | (ROM_CEn & SRAM_CEn & MCP_CSn & FX_GA_CSn);

assign cpu_wrn = FX_GA_CSn | vdc_busy_end | DAn | RW;
assign cpu_rdn = FX_GA_CSn | vdc_busy_end | DAn | ~RW;

//////////////////////////////////////////////////////////////////////
// CPU bus address decoder

logic           ga_int_cs, ga_ext_cs;

// Assert A[1] for upper-halfword or -byte access to 16-bit memory /
// IO, i.e., if one or both of BEn[3:2] are asserted.
assign A1_16 = A[1] | (~&BEn[3:2] & &BEn[1:0]);

assign ROM_CEn  = ~(~MRQn & (A[31:28] == 4'hF));      // F000_0000 .. FFFF_FFFF
assign RAM_CEn  = ~(~MRQn & (A[31:24] == 8'h00));     // 0000_0000 .. 00FF_FFFF
assign SRAM_CEn = ~(~MRQn & (A[31:27] == 5'b1110_0)); // E000_0000 .. E7FF_FFFF
assign MCP_CSn  = ~(~MRQn & (A[31:27] == 5'b1110_1)); // E800_0000 .. EFFF_FFFF
assign FX_GA_CSn= ~((MRQn | (A[31:28] == 4'h8)) & (~BCYSTn | ~DAn)
                    & (ST == 2'b10));
assign unk_cen = ~(RAM_CEn & ROM_CEn & SRAM_CEn & MCP_CSn & FX_GA_CSn);

assign ga_int_cs = ~FX_GA_CSn & (A[30:12] == 19'h00000) &
                   ((A[11:8] < 4'h1) | (A[11:8] > 4'h6));
assign ga_ext_cs = ~FX_GA_CSn & ~ga_int_cs;

//////////////////////////////////////////////////////////////////////
// I/O device control

logic           io_wait, io_wait_trg, io_wait_gap;
logic           io_cy_pend, io_cy_start;
logic [2:0]     io_wait_cnt;
logic [11:1]    io_a_cpu;
logic           io_wrbuf_trg, io_wrbuf_act;
logic [11:1]    io_wrbuf_a;
logic [15:0]    io_wrbuf_d;

// FXGABOAD says: "Write access to normal I/O requires six cycles," or
// 4 wait states.  Assume that read access does, too.
always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        io_wait_cnt <= '0;
        io_cy_pend <= '0;
    end
    else begin
        if (io_wait) begin
            // I/O cycle in progress
            if (~io_busy)
                io_wait_cnt <= io_wait_cnt - 1'd1;
        end
        else if (io_wait_trg)
            // New I/O cycle start
            // Add a clock for back-to-back writes
            io_wait_cnt <= io_cy_pend ? 3'd5 : 3'd4;

        if (~io_cy_pend & io_cy_start)
            io_cy_pend <= io_wrbuf_act;
        else if (io_cy_pend & ~io_wait & io_wait_trg)
            io_cy_pend <= '0;
        else if (io_cy_pend & ~io_readyn & ~io_cy_start)
            io_cy_pend <= '0;
    end
end

assign io_wait = |io_wait_cnt;
assign io_wait_trg = io_wrbuf_act ? (io_cy_pend & ~io_readyn) :
                     (io_cy_start | io_cy_pend);
assign io_wait_gap = (io_wait_cnt == 3'd5); // time to release WRn
assign io_cy_start = ga_ext_cs & ~BCYSTn;
assign io_wrbuf_trg = io_wait_trg & ~RW;

always @* begin
    if (~VDC0_CSn)              io_busy = ~VDC0_BUSYn;
    else if (~VDC1_CSn)         io_busy = ~VDC1_BUSYn;
    else if (~MMC_CSn)          io_busy = ~MMC_BUSYn;
    else                        io_busy = ~io_cs;
end

assign io_readyn = io_busy | io_wait;

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

// I/O device (HuC*) write buffer
// Single-entry buffer that releases CPU bus with 0 wait states

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        io_wrbuf_act <= '0;
    end
    else begin
        if (io_wrbuf_trg) begin
            io_wrbuf_act <= '1;
            io_wrbuf_a <= io_a_cpu;
            io_wrbuf_d <= DI;
        end
        else if (io_wrbuf_act & ~io_readyn) begin
            io_wrbuf_act <= '0;
        end
    end
end

// Signal I/O bus/buffer ready to the CPU bus
//assign fx_ga_readyn = (ga_ext_cs & (io_wrbuf_act ? io_cy_pend : io_readyn)) |
//                      FX_GA_CSn;
assign fx_ga_readyn = (ga_ext_cs & (io_cy_pend | (~io_wrbuf_act & io_readyn))) |
                      FX_GA_CSn;

//////////////////////////////////////////////////////////////////////
// I/O device memory bus interface

logic           io_cs;
logic [11:1]    io_a;
logic [15:0]    io_do;
logic           io_wrn, io_rdn;
logic           io_rdwr_en;

assign io_a_cpu = {A[11:2], A1_16};

always @* begin
    io_cs = ga_ext_cs;
    io_a = io_a_cpu;
    io_do = DI;
    io_wrn = ~ga_ext_cs | cpu_wrn;
    io_rdn = ~ga_ext_cs | cpu_rdn;

    if (io_wrbuf_act) begin
        io_cs = '1;
        io_a = io_wrbuf_a;
        io_do = io_wrbuf_d;
        io_wrn = '0;
        io_rdn = '1;
    end
end

assign io_rdwr_en = io_wait_cnt <= 3'd3;

assign IO_A = io_a[5:1];
assign IO_DO = io_do;
assign IO_WRn = ~io_rdwr_en | io_wrn;
assign IO_RDn = ~io_rdwr_en | io_rdn;

//////////////////////////////////////////////////////////////////////
// I/O device address decoder

assign APU_CSn  = ~(io_cs & (io_a[11:8] == 4'h1)); // HuC6230
assign VPU_CSn  = ~(io_cs & (io_a[11:8] == 4'h2)); // HuC6271
assign VCE_CSn  = ~(io_cs & (io_a[11:8] == 4'h3)); // HuC6261
assign VDC0_CSn = ~(io_cs & (io_a[11:8] == 4'h4)); // HuC6270 #0
assign VDC1_CSn = ~(io_cs & (io_a[11:8] == 4'h5)); // HuC6270 #1
assign MMC_CSn  = ~(io_cs & (io_a[11:8] == 4'h6)); // HuC6272

//////////////////////////////////////////////////////////////////////
// Register interface

logic [6:0]     isr;
logic [6:0]     imr;
logic [2:0]     ilr [7];
logic [3:0]     ahr0, ahr1;

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
    else if (ga_int_cs & ~cpu_wrn) begin
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
    if (ga_int_cs & ~cpu_rdn) begin
        if (~kpc0_csn)
            dout = kpc0_do;
        else if (~kpc1_csn)
            dout = kpc1_do;
        else
            case (A[11:4])
                8'hC0: dout[3:0] = ahr0;
                8'hC4: dout[3:0] = ahr1;
                8'hE0: dout[6:0] = isr;
                8'hE4: dout[6:0] = imr;
                8'hE8: dout[11:0] = {ilr[3], ilr[2], ilr[1], ilr[0]};
                8'hEC: dout[8:0] = {ilr[6], ilr[5], ilr[4]};
                default: ;
            endcase
    end
end

assign DO = ga_int_cs ? dout : IO_DI;

//////////////////////////////////////////////////////////////////////
// HuC6270 AR write snooper

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        ahr0 <= '0;
        ahr1 <= '0;
    end
    else begin
        if ((IO_A[2] == 1'b0) & ~IO_WRn & ~io_readyn) begin
            if (~VDC0_CSn)
                ahr0 <= IO_DO[3:0];
            if (~VDC1_CSn)
                ahr1 <= IO_DO[3:0];
        end
    end
end

//////////////////////////////////////////////////////////////////////
// TMC: Timer Control Unit
// (TODO)

//////////////////////////////////////////////////////////////////////
// KPC: K-Port (Keypad) Control Unit

logic           kpc0_int, kpc1_int, kpc_int;

assign kpc0_csn = ~(ga_int_cs & (A[11:7] == 5'h00)); // 000 .. 07F
assign kpc1_csn = ~(ga_int_cs & (A[11:7] == 5'h01)); // 080 .. 0FF

fx_ga_kpc kpc0
   (
    .RESn(RESn),
    .CLK(CLK),
    .CE(CE),

    .A6(A[6]),
    .A1(A1_16),
    .CSn(kpc0_csn),
    .RDn(cpu_rdn),
    .WRn(cpu_wrn),
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
    .RDn(cpu_rdn),
    .WRn(cpu_wrn),
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
