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

    input         SRES,
    input         INTERP,
    input [1:0]   DIV,

    input [7:0]   KBUS_DI,
    input         KBUS_RHnL,
    input         KBUS_CSn,

    input         SCK_ADPCM_DIV2, // input sample clock / 2
    input         SCK_ADPCM, // ADPCM (input) sample clock
    input         SCK_PCM, // PCM (output) sample clock
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
    if (SCK_ADPCM)
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
        if (SCK_ADPCM) begin
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

        // Refill coded sample buffer or assert hold
        if (~|kbufv_next & SCK_ADPCM_DIV2) begin
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

logic               interp;
logic [2:0]         step;
logic               dec_adpcm, dec_pcm;

logic               c; // code: step sign
logic [2:0]         d; // data: step magnitude
logic [3:0]         dtm;
logic [18:0]        dt;
logic [17:0]        p;
logic signed [19:0] pa;
logic [5:0]         sl;
logic signed [6:0]  sla;
logic [10:0]        ss;

assign interp = INTERP & |DIV;

// dt multiplier is inversely proportional to interpolation (output :
// input sample rate) ratio.
always @* begin
    dtm = 4'd8;                 // 1:1 - 31.47 kHz
    if (interp)
        case (DIV)
            2'b01: dtm = 4'd4;  // 2:1 - 15.73 kHz
            2'b10: dtm = 4'd2;  // 4:1 -  7.84 kHz
            2'b11: dtm = 4'd1;  // 8:1 -  3.93 kHz
            default: ;
        endcase
end

always @(posedge CLK) begin
    ss <= stab[sl];

    if (~RESn | SRES) begin
        step <= '0;
        p <= 18'h20000;
        sl <= '0;
        dt <= '0;
        sla <= '0;
        {c, d} <= '0;
    end
    else begin
        if ((SCK_ADPCM | SCK_PCM) & ~hold) begin
            step <= 3'd1;
            dec_adpcm <= SCK_ADPCM;
            dec_pcm <= SCK_PCM | ~INTERP;

            if (SCK_ADPCM)
                {c, d} <= cs;
        end
        else if (step != 0) begin
            step <= step + 1'd1;
            case (step)
                3'd1: begin
                    if (dec_adpcm) begin
                        dt <= 19'(dtm) * 4'(d + 4'd1) * ss;
                        sla <= $signed(7'(sl)) + 7'(ltab[d]);
                    end
                end
                3'd2: begin
                    if (dec_pcm)
                        pa <= $signed(20'(p)) + $signed(c ? -dt : dt);
                    if (dec_adpcm) begin
                        if (sla > 7'sd48)
                            sl <= 6'd48;
                        else if (sla < 7'sd0)
                            sl <= 6'd0;
                        else
                            sl <= 6'(sla);
                    end
                end
                3'd3: begin
                    if (dec_pcm) begin
                        if (pa > 20'sh3ffff)
                            p <= 18'h3ffff;
                        else if (pa < 20'sh0)
                            p <= 18'h0;
                        else
                            p <= 18'(pa);
                    end
                    step <= '0;
                end
                default: ;
            endcase
        end
    end
end

assign SOUT = p[17:2];

endmodule
