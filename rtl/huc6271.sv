// HuC6271 (RAINBOW)
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - https://github.com/libretro-mirrors/mednafen-git/blob/master/src/pcfx/rainbow.cpp
// - PC-FXGA Authoring Software / GMAKER Starter Kit Plus (Ver. 1.0) / Device Description: HuC6271

module huc6271
   (
    input             CLK,
    input             CE,
    input             RESn,

    // CPU memory / I/O bus interface
    input [3:1]       A,
    input [15:0]      DI,
    output [15:0]     DO,
    input             CSn,
    input             WRn,
    input             RDn,

    // K-BUS interface
    input [7:0]       KBUS_DI,
    output            KBUS_REQ,
    input             KBUS_ACK,

    // R-RAM bank A memory interface
    output reg [12:0] RA_A,
    input [7:0]       RA_DI,
    output reg [7:0]  RA_DO,
    output reg        RA_OEn,
    output reg        RA_WEn,

    // R-RAM bank B memory interface
    output reg [12:0] RB_A,
    input [7:0]       RB_DI,
    output reg [7:0]  RB_DO,
    output reg        RB_OEn,
    output reg        RB_WEn,

    // Video interface
    input             DCK, // pixel clock enable
    input             HSYNC_NEGEDGE,
    output reg [23:0] VD // [7:0] = palette data / [23:0] = {Y,U,V}
    );

logic           si_hdr_det, si_block, si_end;
wor             si_busy;

//////////////////////////////////////////////////////////////////////
// Main FSM

logic [9:0]     h_cnt;
logic [3:0]     v_cnt;
logic           rbsel; // 1: Decode to B, output from A
logic           dec_act;
logic [1:0]     dec_valid;

always @(posedge CLK) begin
    if (~RESn) begin
        h_cnt <= '0;
        v_cnt <= '0;
        rbsel <= '0;
        dec_act <= '0;
        dec_valid <= '0;
    end
    else begin
        if (DCK) begin
            h_cnt <= h_cnt + 1'd1;
        end
        if (HSYNC_NEGEDGE) begin
            if (v_cnt == 4'd15) begin
                dec_valid[rbsel] <= (dec_act & si_end);
                dec_act <= '0;
                rbsel <= ~rbsel;
            end

            h_cnt <= '0;
            if (|v_cnt | dec_act | dec_valid[rbsel])
                v_cnt <= v_cnt + 1'd1;
        end
        if (CE & si_hdr_det)
            dec_act <= '1;
    end
end

//////////////////////////////////////////////////////////////////////
// Compressed data stream injest

typedef enum bit [2:0] {
    SIS_INIT,
    SIS_HDR_TYPE,
    SIS_HDR_LEN1,
    SIS_HDR_LEN2,
    SIS_BLOCK,
    SIS_END
} sis_t;

logic           kbus_req;
sis_t           sist;
logic           si_din_ones;
logic [3:0]     si_hdr;
logic [15:0]    si_len;
logic           si_ready;

wire si_din = kbus_req & KBUS_ACK;
wire si_len_end = si_len < 16'd2; // include 2 length bytes

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        sist <= SIS_INIT;
        si_hdr <= '0;
        si_len <= '1;
        si_din_ones <= '0;
    end
    else begin
        if (si_din)
            si_din_ones <= &KBUS_DI;

        case (sist)
            SIS_INIT:
                if (&KBUS_DI) begin
                    sist <= SIS_HDR_TYPE;
                end
            SIS_HDR_TYPE:
                if (si_din) begin
                    if (si_din_ones) begin
                        si_hdr <= KBUS_DI[3:0];
                        sist <= SIS_HDR_LEN1;
                    end
                    else
                        sist <= SIS_INIT;
                end
            SIS_HDR_LEN1:
                if (si_din) begin
                    si_len[15:8] <= KBUS_DI;
                    sist <= SIS_HDR_LEN2;
                end
            SIS_HDR_LEN2:
                if (si_din) begin
                    si_len[7:0] <= KBUS_DI;
                    sist <= SIS_BLOCK;
                end
            SIS_BLOCK:
                if (si_din) begin
                    si_len <= si_len - 2'd1;
                    if (si_len_end)
                        sist <= SIS_END;
                end
            SIS_END:
                if (~dec_act)
                    sist <= SIS_INIT;
        endcase
    end
end

always @* begin
    kbus_req = RESn;
    si_ready = si_din;
    case (sist)
        SIS_BLOCK: begin
            kbus_req = ~si_busy;
            si_ready &= ~si_din_ones;
        end
        SIS_END:
            kbus_req = '0;
        default: ;
    endcase
end

assign KBUS_REQ = kbus_req;

assign si_hdr_det = (sist == SIS_HDR_LEN1);
assign si_block = (sist == SIS_BLOCK) & ~si_len_end;
assign si_end = (sist == SIS_END);

//////////////////////////////////////////////////////////////////////
// RLE block decoder

typedef enum bit [1:0] {
    RLES_INIT,
    RLES_IN1,
    RLES_IN2,
    RLES_FILL
} rles_t;

rles_t          rles;
logic [7:0]     rle_in1_run, rle_run;
logic [7:0]     rle_in1_cnt, rle_cnt;
logic [12:0]    rle_raddr;
logic [7:0]     rle_rdata;
logic           rle_rwe;

always @* begin
    rle_in1_run = '0;
    rle_in1_cnt = '0;
    case (si_hdr[1:0])
        2'd0: {rle_in1_run[3:0], rle_in1_cnt[3:0]} = KBUS_DI;
        2'd1: {rle_in1_run[4:0], rle_in1_cnt[2:0]} = KBUS_DI;
        2'd2: {rle_in1_run[5:0], rle_in1_cnt[1:0]} = KBUS_DI;
        2'd3: {rle_in1_run[6:0], rle_in1_cnt[0:0]} = KBUS_DI;
        default: ;
    endcase
end

always @(posedge CLK) if (CE) begin
    if (~RESn) begin
        rles <= RLES_INIT;
    end
    else begin
        case (rles)
            RLES_INIT: begin
                rle_run <= '0;
                rle_cnt <= '1;
                rle_raddr <= '0;
                if (si_block)
                    rles <= RLES_IN1;
            end
            RLES_IN1:
                if (si_ready) begin
                    rle_run <= rle_in1_run;
                    rle_cnt <= rle_in1_cnt - 1'd1;
                    rles <= RLES_FILL;
                    if (rle_in1_cnt == '0)
                        rles <= RLES_IN2;
                end
            RLES_IN2:
                if (si_ready) begin
                    rle_cnt <= KBUS_DI;
                    rles <= RLES_FILL;
                end
            RLES_FILL: begin
                if (rle_raddr[0]) begin
                    if (rle_cnt == '0)
                        rles <= RLES_IN1;
                    rle_cnt <= rle_cnt - 1'd1;
                end
                rle_raddr <= rle_raddr + 1'd1;
            end
            default: ;
        endcase

        if (~si_block)
            rles <= RLES_INIT;
    end
end

always @* begin
    rle_rdata = '0;
    rle_rwe = (rles == RLES_FILL);
    if (rle_raddr[0])
        rle_rdata = rle_run;
end

assign si_busy = (rles == RLES_FILL);

//////////////////////////////////////////////////////////////////////
// Video output

localparam [9:0] VO_HACT_START = 10'd56;
localparam [9:0] VO_HACT_END   = VO_HACT_START + 10'd256;

logic [12:0]    vo_raddr;
logic [7:0]     vo_rdata;
logic           vo_ract;
logic           vo_rre;
logic [15:0]    vo_vd;

wire vo_valid = dec_valid[~rbsel];
wire vo_hact = (h_cnt >= VO_HACT_START) & (h_cnt < VO_HACT_END);

always @(posedge CLK) begin
    if (~RESn | ~vo_valid) begin
        vo_raddr <= '0;
        vo_ract <= '0;
    end
    else begin
        if (vo_hact & DCK) begin
            vo_ract <= '1;
        end
        if (vo_ract & CE) begin
            vo_raddr <= vo_raddr + 1'd1;
            if (vo_raddr[0])
                vo_ract <= '0;
        end
    end
end

assign vo_rre = vo_valid;

always @(posedge CLK) if (CE) begin
    if (~vo_valid)
        vo_vd <= '0;
    else if (vo_ract) begin
        if (~vo_raddr[0])
            vo_vd[15:8] <= vo_rdata;
        else
            vo_vd[7:0] <= vo_rdata;
    end
end

always @* begin
    VD = '0;
    if (vo_hact)
        VD[15:0] = vo_vd;
end

//////////////////////////////////////////////////////////////////////
// R-RAM memory interface MUX

always @* begin
    if (~rbsel) begin
        // Decode to A, output from B
        RA_A = rle_raddr;
        RA_DO = rle_rdata;
        RA_OEn = '1;
        RA_WEn = ~rle_rwe;

        RB_A = vo_raddr;
        RB_DO = '0;
        RB_OEn = ~vo_rre;
        RB_WEn = '1;
        vo_rdata = RB_DI;
    end
    else begin
        // Decode to B, output from A
        RB_A = rle_raddr;
        RB_DO = rle_rdata;
        RB_OEn = '1;
        RB_WEn = ~rle_rwe;

        RA_A = vo_raddr;
        RA_DO = '0;
        RA_OEn = ~vo_rre;
        RA_WEn = '1;
        vo_rdata = RA_DI;
    end
end

endmodule
