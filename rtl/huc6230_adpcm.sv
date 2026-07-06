// HuC6230 (SOUNDBOX) ADPCM decoder
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - PC-FXGA Authoring Software / GMAKER Starter Kit Plus (Ver. 1.0) / Device Description: HuC6230

module huc6230_adpcm
   (
    input         CLK,
    input         RESn,

    input [7:0]   KBUS_DI,
    input         KBUS_RHnL,
    input         KBUS_CSn,

    input         DCK, // pixel clock enable
    input         HSYNC_NEGEDGE,

    input         SCK, // ADPCM sample clock
    output [15:0] SOUT
    );

//////////////////////////////////////////////////////////////////////
// K-BUS input buffer

logic [15:0]    kdin, kbuf;
logic [1:0]     kdinv;
logic [3:0]     kbufv, kbufv_next;

logic [3:0]     cs;
logic           hold;

always @* begin
    kbufv_next = kbufv;
    if (SCK)
        kbufv_next = kbufv >> 1;
end

always @(posedge CLK) begin
    if (~RESn) begin
        kdin <= '0;
        kdinv <= '0;
        kbuf <= '0;
        kbufv <= '0;
    end
    else begin
        // Parcel out coded samples
        if (SCK) begin
            if (|kbufv)
                kbufv <= kbufv_next;
        end

        // Read in 4x samples from K-BUS
        if (~KBUS_CSn) begin
            if (KBUS_RHnL)
                kdin[8+:8] <= KBUS_DI;
            else
                kdin[0+:8] <= KBUS_DI;
            kdinv[KBUS_RHnL] <= '1;
        end

        // On the next HSYNC, refill coded sample buffer or assert hold
        if (~|kbufv_next & DCK & HSYNC_NEGEDGE) begin
            if (&kdinv) begin
                kbuf <= kdin;
                kbufv <= '1;
            end
            kdin <= '0;
            kdinv <= '0;
        end
    end
end

assign hold = ~|kbufv;

always @* begin
    casez (kbufv)
        4'b1zzz: cs = kbuf[00+:4];
        4'b01zz: cs = kbuf[04+:4];
        4'b001z: cs = kbuf[08+:4];
        4'b0001: cs = kbuf[12+:4];
        default: cs = '0;
    endcase
end

//////////////////////////////////////////////////////////////////////
// ADPCM decode algorithm

const static logic signed [4:0] ltab [8] = '{
    -5'sd1, -5'sd1, -5'sd1, -5'sd1,
    5'sd2, 5'sd4, 5'sd6, 5'sd8
};

const static logic [10:0] stab [49] =
  '{
    11'd16, 11'd17, 11'd19, 11'd21, 11'd23, 11'd25, 11'd28, 11'd31,
    11'd34, 11'd37, 11'd41, 11'd45, 11'd50, 11'd55, 11'd60, 11'd66,
    11'd73, 11'd80, 11'd88, 11'd97, 11'd107, 11'd118, 11'd130, 11'd143,
    11'd157, 11'd173, 11'd190, 11'd209, 11'd230, 11'd253, 11'd279, 11'd307,
    11'd337, 11'd371, 11'd408, 11'd449, 11'd494, 11'd544, 11'd598, 11'd658,
    11'd724, 11'd796, 11'd876, 11'd963, 11'd1060, 11'd1166, 11'd1282, 11'd1411,
    11'd1552
};

logic [2:0]         step;

logic               c; // code: step sign
logic [2:0]         d; // data: step magnitude
logic [18:0]        dt;
logic [17:0]        p;
logic signed [18:0] pa;
logic [5:0]         sl;
logic signed [6:0]  sla;
logic [10:0]        ss;

always @(posedge CLK) begin
    ss <= stab[sl];

    if (~RESn) begin
        step <= '0;
        p <= 18'h20000;
        sl <= '0;
    end
    else begin
        if (SCK & ~hold) begin
            step <= 3'd1;
            {c, d} <= cs;
        end
        else if (step != 0) begin
            step <= step + 1'd1;
            case (step)
                3'd1: begin
                    dt <= 19'd8 * 4'(d + 4'd1) * ss;
                    sla <= $signed(sl) + 6'(ltab[d]);
                end
                3'd2: begin
                    pa <= $signed(19'(p)) + $signed(c ? -dt : dt);
                    if (sla > 7'sd48)
                        sl <= 6'd48;
                    else if (sla < 7'sd0)
                        sl <= 6'd0;
                    else
                        sl <= 6'(sla);
                end
                3'd3: begin
                    if (pa > 19'sh3ffff)
                        p <= 18'sh3ffff;
                    else if (pa < 19'sh0)
                        p <= 18'sh0;
                    else
                        p <= 18'(pa);
                    step <= '0;
                end
                default: ;
            endcase
        end
    end
end

assign SOUT = p[17:2];

endmodule
