// HuC6272 (KING) DRAM memory controller
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module huc6272_dmc
   (
    input         CLK,
    input         RESn,

    // Client interface
    input [17:0]  A,
    output [15:0] DI,
    input [15:0]  DO,
    input [1:0]   BE, // Byte Enable
    input         WR, // Write / not Read
    input         REQ, // Access request
    output        ACK, // Access acknowledge

    // DRAM interface
    input [15:0]  R_DI,
    output [15:0] R_DO,
    output [8:0]  R_A,
    output        R_OEn,
    output        R_WEn,
    output        R_RASn,
    output        R_LCASn,
    output        R_UCASn
    );

logic               act, trg, rend;
logic [17:0]        a;
logic [8:0]         ao;
logic               cc;
logic               ras, cas, io;

assign trg = REQ;
assign rend = cc & io;

always @(posedge CLK) begin
    if (~RESn) begin
        act <= '0;
    end
    else begin
        if (~act)
            act <= trg;
        else
            act <= ~rend;
    end
end

always @(posedge CLK) begin
    if (~act & trg)
        a <= A;
end

always @(posedge CLK) begin
    if (~RESn) begin
        cc <= '0;
        ao <= '0;
        ras <= 0;
        cas <= 0;
        io <= 0;
    end
    else begin
        if (act) begin
            cc <= ~cc;
            if (~ras) begin
                ras <= '1;
                ao <= a[17:9];
                cc <= '0;
            end
            else if (cc & ~cas) begin
                cas <= '1;
                ao <= a[8:0];
            end
            else if (cc & ~io) begin
                io <= '1;
            end
            else if (cc) begin
                ras <= '0;
                cas <= '0;
                io <= '0;
                ao <= '0;
            end
        end
    end
end

assign DI = R_DI;
assign ACK = rend;

assign R_DO = DO;
assign R_A = ao;
assign R_OEn = ~(act & ~WR);
assign R_WEn = ~(io & WR);
assign R_RASn = ~ras;
assign R_LCASn = ~cas;
assign R_UCASn = ~cas;

endmodule
