// HuC6261 (NEW Iron Guanyin)
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// References:
// - https://github.com/MiSTer-devel/TurboGrafx16_MiSTer/blob/master/rtl/huc6260.vhd
// - PC-FXGA Authoring Software / GMAKER Starter Kit (Ver. 1.1) / Device Description: Hu6261


module huc6261
    (
     input            CLK,
     input            CE,
     input            RESn,

     input            CSn,
     input            WRn,
     input            RDn,
     input            A2,
     input [15:0]     DI,
     output [15:0]    DO,

     // VDC interface
     output           DCK70, // pixel clock enable
     output           DCK70_NEGEDGE,
     output reg       HSYNC_POSEDGE,
     output reg       HSYNC_NEGEDGE,
     output reg       VSYNC_POSEDGE,
     output reg       VSYNC_NEGEDGE,

     input [8:0]      VDC0_VD,
     input [8:0]      VDC1_VD,

     // MMC (HuC6272 KING) and VPU (HuC6271 RAINBOW) video interface
     output           DCKKR, // pixel clock enable
     output           DCKKR_NEGEDGE,
     input            MMC_VDMODE,
     input [23:0]     MMC_VD,
     input            VPU_VDMODE,
     input [23:0]     VPU_VD,

     // NTSC/YUV video output
     output reg [7:0] Y,
     output reg [7:0] U,
     output reg [7:0] V,
     output reg       VSn,
     output reg       HSn,
     output reg       VBL,
     output reg       HBL
     );

localparam [11:0] LEFT_BL_CLOCKS = 12'd457;
localparam [11:0] DISP_CLOCKS = 12'd2160;
localparam [11:0] LINE_CLOCKS = 12'd2730;
localparam [11:0] HS_CLOCKS = 12'd192;
localparam [11:0] HS_OFF = 12'd47;

localparam [8:0] TOTAL_LINES = 9'd263;
localparam [8:0] VS_LINES = 9'd3;
localparam [8:0] TOP_BL_LINES_E = 9'd19;
localparam [8:0] DISP_LINES_E = 9'd242;

localparam [8:0] TOP_BL_LINES = TOP_BL_LINES_E;
localparam [8:0] DISP_LINES = DISP_LINES_E;

typedef struct packed {
    logic [7:0] y, u, v;
} yuv888_t;

typedef struct packed {
    logic bg71;
    logic [3:0] bmg;
    logic sp;
    logic bg;
    logic sp256;
    logic bg256;
    logic [1:0] rsv4;
    logic dc7;
    logic ex;
    logic [1:0] dcc;
} cr_t;

typedef enum bit [1:0] {
    CPE_OFF = 2'b0,
    CPE_ON_1AB,
    CPE_ON_2AB,
    CPE_ON_3AB
} ble_cpe_t;

// Cellophone Surface Setting Register
typedef struct packed {
    logic fb;                   // Front/Back
    logic ed;                   // Enable/Disable
    ble_cpe_t vpu;
    ble_cpe_t mmc_bg3;
    ble_cpe_t mmc_bg2;
    ble_cpe_t mmc_bg1;
    ble_cpe_t mmc_bg0;
    ble_cpe_t vdc_sp;
    ble_cpe_t vdc_bg;
} ble_t;

typedef struct packed {
   logic [3:0] y, u, v;
} blxx_t;

typedef struct packed {
    logic [2:0]     pri;
    logic           key;
    logic [23:0]    vd;
    logic           pal;
    ble_cpe_t       cpe;
} layer_t;

logic [4:0]     ar;
logic [11:0]    h_cnt;
logic [8:0]     v_cnt;

cr_t            cr, cr_next;
logic [8:0]     cpa;
logic [15:0]    cpdin, cpdout;
logic           cpd_wr, cpd_wr_d;
logic [7:0]     vdc_sp_cpao, vdc_bg_cpao, 
                mmc_bg0_cpao, mmc_bg1_cpao, mmc_bg2_cpao, mmc_bg3_cpao,
                vpu_cpao;
logic [2:0]     pri_vdc_bg, pri_vdc_sp, pri_vpu,
                pri_mmc_bg0, pri_mmc_bg1, pri_mmc_bg2, pri_mmc_bg3;
logic [15:0]    ccr, ccr_next;
ble_t           ble, ble_next;
logic [15:0]    spbl, spbl_next;
blxx_t          bl1a, bl1a_next, bl1b, bl1b_next,
                bl2a, bl2a_next, bl2b, bl2b_next,
                bl3a, bl3a_next, bl3b, bl3b_next;

layer_t [3:0]   layers;

//////////////////////////////////////////////////////////////////////
// Register interface

logic [15:0]    dout;

wire cpd_wr_end = ~cpd_wr & cpd_wr_d;

always @(posedge CLK) if (CE) begin
    cpd_wr <= '0;
    cpd_wr_d <= cpd_wr;

    if (~RESn) begin
        cr_next <= '0;
        ar <= '0;
        cpa <= '0;
        vdc_sp_cpao <= '0;
        vdc_bg_cpao <= '0;
        mmc_bg0_cpao <= '0;
        mmc_bg1_cpao <= '0;
        mmc_bg2_cpao <= '0;
        mmc_bg3_cpao <= '0;
        vpu_cpao <= '0;
        pri_vdc_bg <= '0;
        pri_vdc_sp <= '0;
        pri_vpu <= '0;
        pri_mmc_bg0 <= '0;
        pri_mmc_bg1 <= '0;
        pri_mmc_bg2 <= '0;
        pri_mmc_bg3 <= '0;
        ccr_next <= '0;
        ble_next <= '0;
        spbl_next <= '0;
        bl1a_next <= '0;
        bl1b_next <= '0;
        bl2a_next <= '0;
        bl2b_next <= '0;
        bl3a_next <= '0;
        bl3b_next <= '0;
    end
    else begin
        if (cpd_wr_end)
            cpa <= cpa + 1'd1;

        if (~CSn & ~WRn) begin
            case (A2)
                1'b0: begin
                    ar <= DI[4:0];
                end
                1'b1: begin
                    case (ar)
                        5'd00:
                            cr_next <= DI[14:0];
                        5'd01:
                            cpa <= DI[8:0];
                        5'd02: begin
                            cpdin <= DI[15:0];
                            cpd_wr <= '1;
                        end
                        5'd04: begin
                            vdc_sp_cpao <= DI[15:8];
                            vdc_bg_cpao <= DI[7:0];
                        end
                        5'd05: begin
                            mmc_bg1_cpao <= DI[15:8];
                            mmc_bg0_cpao <= DI[7:0];
                        end
                        5'd06: begin
                            mmc_bg3_cpao <= DI[15:8];
                            mmc_bg2_cpao <= DI[7:0];
                        end
                        5'd07:
                            vpu_cpao <= DI[7:0];
                        5'h08: begin
                            pri_vdc_bg <= DI[0+:3];
                            pri_vdc_sp <= DI[4+:3];
                            pri_vpu <= DI[8+:3];
                        end
                        5'h09: begin
                            pri_mmc_bg0 <= DI[0+:3];
                            pri_mmc_bg1 <= DI[4+:3];
                            pri_mmc_bg2 <= DI[8+:3];
                            pri_mmc_bg3 <= DI[12+:3];
                        end
                        5'h0d:
                            ccr_next <= DI[15:0];
                        5'h0e:
                            ble_next <= DI[15:0];
                        5'h0f:
                            spbl_next <= DI[15:0];
                        5'h10:
                            bl1a_next <= DI[11:0];
                        5'h11:
                            bl1b_next <= DI[11:0];
                        5'h12:
                            bl2a_next <= DI[11:0];
                        5'h13:
                            bl2b_next <= DI[11:0];
                        5'h14:
                            bl3a_next <= DI[11:0];
                        5'h15:
                            bl3b_next <= DI[11:0];
                        default: ;
                    endcase
                end
            endcase
        end
    end
end

always @* begin
    dout = '0;
    case (A2)
        1'b0: begin
            dout[4:0] = ar;
            dout[13:5] = v_cnt;
        end
        1'b1: begin
            case (ar)
                5'd03:
                    dout[15:0] = cpdout;
                5'h08: begin
                    dout[0+:3] = pri_vdc_bg;
                    dout[4+:3] = pri_vdc_sp;
                    dout[8+:3] = pri_vpu;
                end
                5'h09: begin
                    dout[0+:3] = pri_mmc_bg0;
                    dout[4+:3] = pri_mmc_bg1;
                    dout[8+:3] = pri_mmc_bg2;
                    dout[12+:3] = pri_mmc_bg3;
                end
                5'h0d:
                    dout = ccr_next;
                5'h0e:
                    dout = ble_next;
                5'h0f:
                    dout = spbl_next;
                5'h10:
                    dout[11:0] = bl1a_next;
                5'h11:
                    dout[11:0] = bl1b_next;
                5'h12:
                    dout[11:0] = bl2a_next;
                5'h13:
                    dout[11:0] = bl2b_next;
                5'h14:
                    dout[11:0] = bl3a_next;
                5'h15:
                    dout[11:0] = bl3b_next;
                default: ;
            endcase
        end
    endcase
end

assign DO = (~CSn & ~RDn) ? dout : '0;

//////////////////////////////////////////////////////////////////////
// Video counter

logic           multires, multires_p;

wire h_wrap = h_cnt == (LINE_CLOCKS - 1'd1);
wire v_wrap = v_cnt == (TOTAL_LINES - 1'd1);

always @(posedge CLK) begin
    if (~RESn) begin
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
end

// Some registers update only every line or frame.
always @(posedge CLK) begin
    if (~RESn) begin
        cr <= '0;
        ccr <= '0;
        ble <= '0;
        spbl <= '0;
        bl1a <= '0;
        bl1b <= '0;
        bl2a <= '0;
        bl2b <= '0;
        bl3a <= '0;
        bl3b <= '0;
        multires_p <= '0;
        multires <= '0;
    end
    else begin
        if (h_wrap) begin
            cr <= cr_next;
            ccr <= ccr_next;
            ble <= ble_next;
            spbl <= spbl_next;
            bl1a <= bl1a_next;
            bl1b <= bl1b_next;
            bl2a <= bl2a_next;
            bl2b <= bl2b_next;
            bl3a <= bl3a_next;
            bl3b <= bl3b_next;
        end

        if ((v_cnt >= TOP_BL_LINES) & (v_cnt < (TOP_BL_LINES + DISP_LINES)) &
            (cr.dc7 != cr_next.dc7))
            multires_p <= '1;

        if (v_cnt == TOP_BL_LINES + DISP_LINES) begin
            multires <= multires_p;
            multires_p <= '0;
        end
    end
end

task dump_regs();
    $display("HuC6261 register dump");
    $display("  00=%x 04=%x 05=%x 06=%x 07=%x",
             cr,
             {vdc_sp_cpao, vdc_bg_cpao},
             {mmc_bg1_cpao, mmc_bg0_cpao},
             {mmc_bg3_cpao, mmc_bg2_cpao},
             {8'b0, vpu_cpao});
    $display("  08=%x 09=%x 0d=%x 0e=%x 0f=%x",
             {5'b0, pri_vpu, 1'b0, pri_vdc_sp, 1'b0, pri_vdc_bg},
             {1'b0, pri_mmc_bg3, 1'b0, pri_mmc_bg2, 1'b0, pri_mmc_bg1, 1'b0, pri_mmc_bg0},
             ccr, ble, spbl);
    $display("  10=%x 11=%x 12=%x 13=%x 14=%x 15=%x",
             bl1a, bl1b, bl2a, bl2b, bl3a, bl3b);
endtask

//////////////////////////////////////////////////////////////////////
// "Fast" (dot processing) clock generator
//
// Rate is 4x the 256 pixel clock

logic           ckenf_cnt;
logic           ckenfp, ckenf;

always @(posedge CLK) begin
    ckenfp <= '0;

    if (~RESn) begin
        ckenf_cnt <= '0;
    end
    else begin
        ckenf_cnt <= ~ckenf_cnt;

        if ((ckenf_cnt && h_cnt < (LINE_CLOCKS - 12'(2+1))) | 
            h_wrap) begin
            ckenf_cnt <= '0;
            ckenfp <= '1;
        end
    end

    ckenf <= ckenfp;
end

//////////////////////////////////////////////////////////////////////
// VDC (HuC6270) Pixel clock generator
//
// Variable rate for 256 or 320 horizontal pixels

logic [2:0]     cken70_cnt;
logic           cken70, cken70_ne;

always @(posedge CLK) begin
    cken70 <= '0;
    cken70_ne <= '0;

    if (~RESn) begin
        cken70_cnt <= '0;
    end
    else begin
        cken70_cnt <= cken70_cnt + 1'd1;

        if ((((multires & (cken70_cnt == 3'd3))
              | (cr.dc7 == 1'b0 & ((cken70_cnt == 3'd7))))
             & (h_cnt < (LINE_CLOCKS - 12'(2+1))))
            | (cr.dc7 == 1'b1 & (cken70_cnt == 3'd5))
            | h_wrap) begin
            cken70_cnt <= '0;
            cken70 <= '1;
        end
        if (((cr.dc7 == 1'b0) & (cken70_cnt == 3'd3))
            | ((cr.dc7 == 1'b1) & (cken70_cnt == 3'd2)))
            cken70_ne <= '1;
    end
end

assign DCK70 = cken70;
assign DCK70_NEGEDGE = cken70_ne;

//////////////////////////////////////////////////////////////////////
// VPU (HuC6271 RAINBOW) / MMC (HuC6272 KING) Pixel clock generator
//
// Fixed rate for 256 horizontal pixels

logic [2:0]     ckenkr_cnt;
logic           ckenkr, ckenkr_ne;

always @(posedge CLK) begin
    ckenkr <= '0;
    ckenkr_ne <= '0;

    if (~RESn) begin
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
        if (ckenkr_cnt == 3'd3)
            ckenkr_ne <= '1;
    end
end

assign DCKKR = ckenkr;
assign DCKKR_NEGEDGE = ckenkr_ne;

//////////////////////////////////////////////////////////////////////
// VDC MUX

logic             vdc_en, vdc_key;
logic [8:0]       vdc_vd;
logic             vdc_spbg;
logic [8:0]       vdc_cpa_bg, vdc_cpa_sp;
logic             vdc_cce;

wire vdc0_key = VDC0_VD[7:0] != '0;
wire vdc1_key = VDC1_VD[7:0] != '0;

// "Upper" 6270 has priority over "lower".
assign vdc_vd = ~vdc1_key ? VDC0_VD : VDC1_VD;
assign vdc_spbg = vdc_vd[8];
assign vdc_en = vdc_spbg ? cr.sp : cr.bg;
assign vdc_key = vdc_en & (vdc0_key | vdc1_key);

assign vdc_cpa_bg = {vdc_bg_cpao, 1'b0} + {1'b0, vdc_vd[7:0]};
assign vdc_cpa_sp = {vdc_sp_cpao, 1'b0} + {1'b0, vdc_vd[7:0]};
assign vdc_cce = spbl[vdc_vd[7:4]];

assign layers[0].pri = vdc_spbg ? pri_vdc_sp : pri_vdc_bg;
assign layers[0].key = vdc_key;
assign layers[0].vd  = 24'(vdc_spbg ? vdc_cpa_sp : vdc_cpa_bg);
assign layers[0].pal = '1;
assign layers[0].cpe = ble_cpe_t'(vdc_spbg ? (ble.vdc_sp & {2{vdc_cce}})
                                  : ble.vdc_bg);

//////////////////////////////////////////////////////////////////////
// MMC (KING) video input

logic [8:0]     mmc_cpa;
logic [23:0]    mmc_vd;
logic           mmc_en, mmc_key;

assign mmc_en = cr.bmg[0];

assign mmc_cpa = {mmc_bg0_cpao, 1'b0} + {1'b0, MMC_VD[7:0]};

always @* begin
    if (~MMC_VDMODE) begin // palette
        mmc_key = mmc_en & |MMC_VD[0+:8];
        mmc_vd = 24'(mmc_cpa);
    end
    else begin // YUV
        mmc_key = mmc_en & |MMC_VD[16+:8];
        mmc_vd = MMC_VD;
    end
end

// MMC BG0
assign layers[1].pri = pri_mmc_bg0;
assign layers[1].key = mmc_key;
assign layers[1].vd  = mmc_vd;
assign layers[1].pal = ~MMC_VDMODE;
assign layers[1].cpe = ble.mmc_bg0;

//////////////////////////////////////////////////////////////////////
// VPU (RAINBOW) video input

logic [8:0]     vpu_cpa;
logic [23:0]    vpu_vd;
logic           vpu_en, vpu_key;

assign vpu_en = cr.bg71;

assign vpu_cpa = {vpu_cpao, 1'b0} + {2'b0, VPU_VD[6:0]};

always @* begin
    if (~VPU_VDMODE) begin // palette
        vpu_key = vpu_en & |VPU_VD[0+:8];
        vpu_vd = 24'(vpu_cpa);
    end
    else begin // YUV
        vpu_key = '1; // TODO
        vpu_vd = VPU_VD;
    end
end

assign layers[2].pri = pri_vpu;
assign layers[2].key = vpu_key;
assign layers[2].vd  = vpu_vd;
assign layers[2].pal = ~VPU_VDMODE;
assign layers[2].cpe = ble.vpu;

//////////////////////////////////////////////////////////////////////
// Layer priority encoder

logic [1:0]     prio_idx [3];
logic [1:0]     prio_sel;
logic [1:0]     prio_out;

// Sort layers from lowest to highest priority
always @(posedge CLK) begin
    case ({layers[1].pri < layers[0].pri,
           layers[2].pri < layers[1].pri,
           layers[2].pri < layers[0].pri})
        3'b111: begin prio_idx[0] <= 2'd2; prio_idx[1] <= 2'd1; prio_idx[2] <= 2'd0; end
        3'b101: begin prio_idx[0] <= 2'd1; prio_idx[1] <= 2'd2; prio_idx[2] <= 2'd0; end
        3'b011: begin prio_idx[0] <= 2'd2; prio_idx[1] <= 2'd0; prio_idx[2] <= 2'd1; end
        3'b100: begin prio_idx[0] <= 2'd1; prio_idx[1] <= 2'd0; prio_idx[2] <= 2'd2; end
        3'b010: begin prio_idx[0] <= 2'd0; prio_idx[1] <= 2'd2; prio_idx[2] <= 2'd1; end
        3'b000: begin prio_idx[0] <= 2'd0; prio_idx[1] <= 2'd1; prio_idx[2] <= 2'd2; end
        default:begin prio_idx[0] <= 2'dX; prio_idx[1] <= 2'dX; prio_idx[2] <= 2'dX; end
    endcase
end

// Selected priority
assign prio_out = prio_idx[prio_sel];

//////////////////////////////////////////////////////////////////////
// Video layer MUX

layer_t vmux;
logic   vmux_low_chroma;

always @* begin
    vmux = layers[prio_out];
    if (vmux_low_chroma && prio_sel == 2'd0 && ~vmux.key) begin
        vmux.vd = '0;
        vmux.pal = '1;
    end
end

//////////////////////////////////////////////////////////////////////
// Palette RAM address generator

logic [8:0]       cpa_out;

always @* begin
    cpa_out = '0;
    if (vmux.pal)
        cpa_out = vmux.vd[8:0];
end

//////////////////////////////////////////////////////////////////////
// Color palette RAM

logic [15:0]    cp_out;

dpram #(.addr_width(9), .data_width(16)) cpram
   (
    .clock(CLK),
    .address_a(cpa),
    .data_a(cpdin),
    .enable_a(1'b1),
    .wren_a(cpd_wr),
    .q_a(cpdout),
    .cs_a(1'b1),

    .address_b(cpa_out),
    .data_b('0),
    .enable_b(1'b1),
    .wren_b('0),
    .q_b(cp_out),
    .cs_b(1'b1)
    );

//////////////////////////////////////////////////////////////////////
// Video layer @ YUV

logic [23:0]    mix_vd;
yuv888_t        mix_out;

layer_t         mix;

always @(posedge CLK) begin
    mix_vd <= vmux.vd;
end

always @* begin
    if (vmux.pal) begin
        mix_out.y = cp_out[8+:8];
        mix_out.u = {cp_out[7:4], 4'b0000};
        mix_out.v = {cp_out[3:0], 4'b0000};
    end
    else
        mix_out = yuv888_t'(mix_vd);
end

assign mix.vd = mix_out;
assign mix.key = vmux.key;
assign mix.cpe = vmux.cpe;

//////////////////////////////////////////////////////////////////////
// Chroma key and Cellophane Dot Processing

yuv888_t        ccdp_sel1, ccdp_sel2, ccdp_reg1, ccdp_reg2;
logic           ccdp_sel1_ccr;
logic           ccdp_sel2_cc;
blxx_t          ccdp_m, ccdp_n;
yuv888_t        ccdp_ccout;
logic           ccdp_reg1_en;
logic           ccdp_low_chroma;
logic           ccdp_front, ccdp_back;

// There are four processing phases per dot clock.
wire [1:0] ccdp_phase = ckenkr_cnt[2:1];

// One dot requires three processing phases, plus one if front/back
// cellphane is enabled.
wire [1:0] ccdp_last_phase = 2'd2 + ble.ed;

// Cellophane calculation
function [7:0] ccdp_cc(input [7:0] m, input [7:0] n, 
                       input [3:0] a, input [3:0] b,
                       input       uv);
logic signed [12:0] ma;
    if (uv) begin
        m -= 8'sh80;
        n -= 8'sh80;
        ma = $signed(m) * $signed(5'(a));
        ma += $signed(n) * $signed(5'(b));
        ma += 13'(11'sh80 << 3);
    end
    else begin
        ma = m * a;
        ma += n * b;
    end
    ccdp_cc = ma[10:3];
    if (ma[11])
        ccdp_cc = 8'hff;
endfunction

function blxx_t get_ccdp_m(input ble_cpe_t cpe);
    case (cpe)
        CPE_OFF:    get_ccdp_m = '0;
        CPE_ON_1AB: get_ccdp_m = bl1a;
        CPE_ON_2AB: get_ccdp_m = bl2a;
        CPE_ON_3AB: get_ccdp_m = bl3a;
        default: ;
    endcase
endfunction

function blxx_t get_ccdp_n(input ble_cpe_t cpe);
    case (cpe)
        CPE_OFF:    get_ccdp_n = '0;
        CPE_ON_1AB: get_ccdp_n = bl1b;
        CPE_ON_2AB: get_ccdp_n = bl2b;
        CPE_ON_3AB: get_ccdp_n = bl3b;
        default: ;
    endcase
endfunction

// Front/back cellophane selected
assign ccdp_front = ble.ed &  ble.fb & (ccdp_phase == 2'd3);
assign ccdp_back  = ble.ed & ~ble.fb & (ccdp_phase == 2'd0);

always @* begin
    ccdp_m = get_ccdp_m(mix.cpe);
    ccdp_n = get_ccdp_n(mix.cpe);
    if (ccdp_front) begin
        ccdp_m = bl1a;
        ccdp_n = bl1b;
    end
end

always @* begin
    ccdp_ccout.y = ccdp_cc(ccdp_sel1.y, ccdp_reg1.y, ccdp_m.y, ccdp_n.y, 0);
    ccdp_ccout.u = ccdp_cc(ccdp_sel1.u, ccdp_reg1.u, ccdp_m.u, ccdp_n.u, 1);
    ccdp_ccout.v = ccdp_cc(ccdp_sel1.v, ccdp_reg1.v, ccdp_m.v, ccdp_n.v, 1);
end

// Selector 1: Fixed color -or- selected priority layer
always @* begin
    ccdp_sel1 = yuv888_t'(mix.vd);
    if (ccdp_sel1_ccr) begin
        ccdp_sel1.y = ccr[8+:8];
        ccdp_sel1.u = {ccr[7:4], 4'b0000};
        ccdp_sel1.v = {ccr[3:0], 4'b0000};
    end
end

// Selector 2: Selector 1 -or- cellophane calculation
assign ccdp_sel2 = ccdp_sel2_cc ? ccdp_ccout : ccdp_sel1;

// Register 1: Latches selector 2 at fast clock rate
always @(posedge CLK) if (ckenf) begin
    if (ccdp_reg1_en)
        ccdp_reg1 <= ccdp_sel2;
end

// Register 2: Latches register 1 at output dot clock rate
always @(posedge CLK) if (DCK70) begin
    ccdp_reg2 <= ccdp_reg1;
end

// Logic to glue it all together
always @* begin
    prio_sel = '0;
    ccdp_sel1_ccr = '0;
    ccdp_sel2_cc = '0;
    ccdp_reg1_en = '0;
    ccdp_low_chroma = '0;

    if (cr.dc7) begin
        prio_sel = 2'd2;
        ccdp_reg1_en = '1;
    end
    else begin
        if (ccdp_front | ccdp_back) begin
            // Apply front/back cellophane
            ccdp_sel1_ccr = '1;
            ccdp_sel2_cc = ccdp_front;
            ccdp_reg1_en = '1;
        end
        if (~ccdp_sel1_ccr) begin
            if (ccdp_phase <= ccdp_last_phase) begin
                prio_sel = ccdp_phase - 1'(ble.ed & ~ble.fb);
                ccdp_reg1_en = mix.key;
                ccdp_sel2_cc = mix.cpe != CPE_OFF;
            end
            if (ccdp_phase == 2'd0 & ~ccdp_back) begin
                // Special case for lowest priority layer
                ccdp_low_chroma = '1;
                ccdp_reg1_en = '1;
            end
        end
    end
end

assign vmux_low_chroma = ccdp_low_chroma;

//////////////////////////////////////////////////////////////////////
// Sync generators

logic [11:0]    hsync_start_pos, hsync_end_pos;
logic           hbl_ff = '1, vbl_ff = '1;

always @* begin
    hsync_start_pos = (cr.dc7 ? (LINE_CLOCKS - 12'd6) : 12'd8) - 1'd1;
    hsync_end_pos = (cr.dc7 ? (12'd468 - 12'd6) : (12'd8 + 12'd464)) - 1'd1;
end

// These syncs are for the VDCs.
always @(posedge CLK) begin
    HSYNC_NEGEDGE <= (h_cnt == hsync_start_pos);
    HSYNC_POSEDGE <= (h_cnt == hsync_end_pos);
    VSYNC_NEGEDGE <= ((v_cnt == VS_LINES - 1'd1) & h_wrap);
    VSYNC_POSEDGE <= (v_wrap & h_wrap);
end

// These syncs are for the actual video output.
always @(posedge CLK) begin
    if (h_cnt == HS_OFF)
        HSn <= '0;
    else if (h_cnt == HS_OFF + HS_CLOCKS)
        HSn <= '1;

    if (v_cnt == 9'd0)
        VSn <= '0;
    else if (v_cnt == VS_LINES)
        VSn <= '1;
end

// Blanking periods
always @(posedge CLK) begin
    if (h_cnt == LEFT_BL_CLOCKS)
        hbl_ff <= '0;
    else if (h_cnt == LEFT_BL_CLOCKS + DISP_CLOCKS)
        hbl_ff <= '1;

    if (v_cnt == TOP_BL_LINES)
        vbl_ff <= '0;
    else if (v_cnt == TOP_BL_LINES + DISP_LINES)
        vbl_ff <= '1;
end

//////////////////////////////////////////////////////////////////////
// Final output

always @(posedge CLK) if (DCK70) begin
    VBL <= vbl_ff;
    HBL <= hbl_ff;

    Y <= ccdp_reg2.y;
    U <= ccdp_reg2.u;
    V <= ccdp_reg2.v;
end

endmodule
