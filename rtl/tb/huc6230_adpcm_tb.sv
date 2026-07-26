// SOUNDBOX ADPCM decode testbench
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

`timescale 1us / 1ns

module huc6230_adpcm_tb;

initial begin
    $timeformat(-6, 0, " us", 1);

    $dumpfile("huc6230_adpcm_tb.vcd");
    $dumpvars();
end

//////////////////////////////////////////////////////////////////////

logic           reset = 1;
logic           clk = 1;
logic           ce = 0;

initial forever begin :ckgen
    #0.01 clk = ~clk; // 50 MHz
end

always @(posedge clk) begin :cegen
    ce <= ~ce;
end

//////////////////////////////////////////////////////////////////////

logic [11:0]    h_cnt;
logic [8:0]     v_cnt;
logic [2:0]     ckenkr_cnt;
logic           ckenkr;
logic           dck;
logic           hsync_negedge;

localparam [11:0] LINE_CLOCKS = 12'd2730;
localparam [8:0] TOTAL_LINES = 9'd263;

wire h_wrap = h_cnt == (LINE_CLOCKS - 1'd1);
wire v_wrap = v_cnt == (TOTAL_LINES - 1'd1);

always @(posedge clk) begin
    if (reset) begin
        h_cnt <= '0;
        v_cnt <= '0;
    end
    else begin
        if (~h_wrap)
            h_cnt <= h_cnt + 1'd1;
        else begin
            h_cnt <= '0;
            if (~v_wrap)
                v_cnt <= v_cnt + 1'd1;
            else
                v_cnt <= '0;
        end
    end

    ckenkr <= '0;

    if (reset) begin
        ckenkr_cnt <= '0;
    end
    else begin
        ckenkr_cnt <= ckenkr_cnt + 1'd1;

        if (((ckenkr_cnt == 3'd7)
             & (h_cnt < (LINE_CLOCKS - 12'(2+1))))
            | h_wrap) begin
            ckenkr_cnt <= '0;
            ckenkr <= '1;
        end
    end

    hsync_negedge <= (h_cnt == 12'd7);
end

assign dck = ckenkr;

//////////////////////////////////////////////////////////////////////

logic [5:1]     a;
logic [7:0]     io_din;
logic           io_csn = '1;
logic           io_wrn = '1;

logic [7:0]     kbus_di;
logic           kbus_rhnl;
logic [1:0]     kbus_csn;

huc6230 apu
   (
    .CLK(clk),
    .CE(ce),
    .RESn(~reset),

    .A(a),
    .DI(io_din),
    .CSn(io_csn),
    .WRn(io_wrn),

    .KBUS_DI(kbus_di),
    .KBUS_RHnL(kbus_rhnl),
    .KBUS_CSn(kbus_csn),

    .DCK(dck),
    .HSYNC_NEGEDGE(hsync_negedge),

    .SLOUT(),
    .SROUT()
    );

//////////////////////////////////////////////////////////////////////

integer fdat;
logic [15:0] frbuf;
logic apu_kbus_en = '0;
integer hs_cnt = 0;
logic   kbus_trg = '0;
logic   side = 0;
wire [1:0] adpcm_div = 2'b01;

always @(posedge clk) if (dck) begin
    if (fdat != -1 && v_cnt == 9'd6)
        apu_kbus_en <= '1;
end

initial begin
    fdat = $fopen("adpcm.bin", "r");
    kbus_di = '0;
    kbus_csn = '1;
    kbus_rhnl = '0;
    side = 0;
end
always @(posedge clk) if (dck & hsync_negedge) begin
    if (apu_kbus_en) begin
        hs_cnt <= hs_cnt + 1;
        if (hs_cnt == (2 ** (adpcm_div + 1) - 1)) begin
            kbus_trg <= '1;
            hs_cnt <= 0;
        end
    end
end
always @(posedge clk) if (ce) begin
integer code;
    if (~&kbus_csn) begin
        kbus_csn <= '1;
        kbus_di <= '0;
    end
    else if (kbus_trg) begin
        if (~kbus_rhnl && side == 0) begin
            code = $fread(frbuf, fdat, 0, 2);
            if (code != 2) begin
                kbus_trg <= '0;
                apu_kbus_en <= '0;
                $fclose(fdat);
                fdat = -1;
            end
        end
        if (~kbus_rhnl && code == 2) begin
            kbus_rhnl <= '1;
            kbus_csn[side] <= '0;
            kbus_di <= frbuf[8+:8];
        end
        else if (kbus_rhnl) begin
            kbus_rhnl <= '0;
            kbus_csn[side] <= '0;
            kbus_di <= frbuf[0+:8];
            side <= ~side;
            if (side)
                kbus_trg <= '0;
        end
    end
end

//////////////////////////////////////////////////////////////////////

task reg_write(input [4:0] rs, input [7:0] v);
    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    a[5:1] <= rs;
    io_din <= v;
    io_wrn <= 0;
    io_csn <= 0;

    @(posedge clk) ;
    while (!ce)
        @(posedge clk) ;
    io_din <= 'X;
    io_wrn <= 1;
    io_csn <= 1;
endtask

//////////////////////////////////////////////////////////////////////

initial #0 begin
    #10 @(posedge clk) reset <= 0;
    #2 @(posedge clk) ;

    reg_write(5'h10, {6'b000011, adpcm_div});

    #(16e3) $finish;
end

endmodule


// Local Variables:
// compile-command: "iverilog -g2012 -grelative-include -s huc6230_adpcm_tb -o huc6230_adpcm_tb.vvp ../huc6230.sv huc6230_adpcm_tb.sv && ./huc6230_adpcm_tb.vvp"
// End:
