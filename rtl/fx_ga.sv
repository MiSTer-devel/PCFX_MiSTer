// PC-FX Gate Array
//
// Implement enough of the chip to appease the BIOS.
//
// Copyright (c) 2025 David Hunter
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
   input [1:0]   ST,
   input         DAn,
   input         MRQn,
   input         RW,
   input         BCYSTn,
   output        READYn,
   output        SZRQn,

   // Address decoder
   output        ROM_CEn,
   output        RAM_CEn,
   output        IO_CEn,

   output        FX_GA_CSn,
   output        HUC6261_CSn,
   output        HUC6270_0_CSn,
   output        HUC6270_1_CSn,

   // Memory control
   input         ROM_READYn,
   input         RAM_READYn,

   // Device control
   output        WRn,
   output        RDn,

   // Device interrupts
   input [3:0]   DINT,

   // CPU interrupt interface
   output        CINT,
   output [3:0]  CINTVn,
   output        CNMIn
   );

//////////////////////////////////////////////////////////////////////
// Memory / I/O bus interface

logic           unk_cen;

assign READYn = unk_cen & ROM_READYn & RAM_READYn & IO_CEn;
assign SZRQn = ~unk_cen | (ROM_CEn & IO_CEn);

//////////////////////////////////////////////////////////////////////
// Address decoder / device control

assign ROM_CEn = ~(~MRQn & (A[31:28] == 4'hF));
assign RAM_CEn = ~(~MRQn & (A[31:24] == 8'h00));
assign IO_CEn = ~((MRQn | (A[31:28] == 4'h8)) & (~BCYSTn | ~DAn)
                  & (ST == 2'b10));
assign unk_cen = ~(RAM_CEn & ROM_CEn & IO_CEn);

assign FX_GA_CSn = IO_CEn | ~(HUC6261_CSn & HUC6270_0_CSn & HUC6270_1_CSn);

assign HUC6261_CSn   = ~(~IO_CEn & (A[27:8] == 20'h00003));
assign HUC6270_0_CSn = ~(~IO_CEn & (A[27:8] == 20'h00004));
assign HUC6270_1_CSn = ~(~IO_CEn & (A[27:8] == 20'h00005));

assign WRn = IO_CEn | DAn | RW;
assign RDn = IO_CEn | DAn | ~RW;

//////////////////////////////////////////////////////////////////////
// Register interface

logic [1:0]     ktrg, ktrg_set, ktrg_reset;
logic [1:0]     kmod;
logic [1:0]     kios;
logic [1:0]     kend;
logic [1:0]     kd_rd;

logic [6:0]     isr;
logic [6:0]     imr;
logic [2:0]     ilr [7];

logic [15:0]    dout;

always @(posedge CLK) if (CE) begin
    ktrg_set <= '0;

    if (~RESn) begin
        kmod <= '1;
        kios <= '1;

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
            8'h00: begin
                {kios[0], kmod[0], ktrg_set[0]} <= DI[2:0];
            end
            8'h08: begin
                {kios[1], kmod[1], ktrg_set[1]} <= DI[2:0];
            end
            8'hE4: imr <= DI[6:0];
            8'hE8: {ilr[3], ilr[2], ilr[1], ilr[0]} <= DI[11:0];
            8'hEC: {ilr[6], ilr[5], ilr[4]} <= DI[8:0];
            default: ;
        endcase
    end
end

always @(posedge CLK) if (CE) begin
    kd_rd <= '0;

    if (~FX_GA_CSn & ~RDn) begin
        case (A[11:4])
            8'h04: kd_rd[0] <= '1;
            8'h0C: kd_rd[1] <= '1;
            default: ;
        endcase
    end
end

always @* begin
    dout = '0;
    if (~FX_GA_CSn & ~RDn) begin
        case (A[11:4])
            8'h00: dout[3:0] = {kend[0], kios[0], kmod[0], ktrg[0]};
            8'h08: dout[3:0] = {kend[1], kios[1], kmod[1], ktrg[1]};
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

assign ktrg_reset = ktrg_set;

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        ktrg <= '0;
    end
    else begin
        ktrg <= (ktrg | ktrg_set) & ~ktrg_reset;
        kend <= (kend | ktrg_reset) & ~kd_rd;
    end
end

//////////////////////////////////////////////////////////////////////
// ITC: Interrupt Control Unit
//
// TODO:
// - AERR Address Error
// - Internal interrupt sources: INTKP (4), INTEX (5), INTTM (6)

logic [6:0]     eisr;           // un-masked (enabled) ISR
logic [2:0]     hail;           // highest active interrupt level

assign isr[6:4] = '0;
assign isr[3:0] = DINT[3:0];

assign eisr = isr & ~imr;

// Identify the highest level in the set of enabled active interrupts.
always @* begin
    hail = '0;
    for (int i = 0; i <= 6; i++)
        if (eisr[i] & (ilr[i] > hail))
            hail = ilr[i];
end

assign CINT = |eisr;
assign CINTVn = {1'b0, ~hail};
assign CNMIn = '1;

endmodule
