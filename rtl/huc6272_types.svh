// HuC6272 (KING) internal data types
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

//////////////////////////////////////////////////////////////////////
// SCSI

typedef struct packed {
    logic [7:0]     dout, txbuf;
    
    logic           assert_rst;
    logic           assert_ack;
    logic           assert_sel;
    logic           assert_atn;
    logic           assert_data;
    logic           assert_io;
    logic           assert_cd;
    logic           assert_msg;
    
    logic           dma_mode;
    logic           dma_kba;
    logic           dma_kpage;
    logic [16:0]    dma_ka;
    logic [17:1]    dma_byte_cnt;
    logic           dma_en;
    logic           dma_int_en;
    
    logic           reset_int;
    logic           reset_dma_end_int;
    logic           start_dma_rx, start_dma_tx;
    logic           rxbuf_rd;
    logic           txbuf_wr;
} rf_scsi_t;

typedef struct packed {
    logic [7:0]     cur_bus_stat;
    logic           phase_match;
    logic           block_int;
    logic           atn, ack;
    logic [7:0]     din, rxbuf;
    logic           dma_req;
    logic           int_req_act;
    logic           dma_next;
    logic           dma_end;
} st_scsi_t;

//////////////////////////////////////////////////////////////////////
// Video

typedef enum bit [3:0] {
    BGF_UNUSED = 4'h0,
    BGF_INT_DOT_4 = 4'h1,
    BGF_INT_DOT_16 = 4'h2,
    BGF_INT_DOT_256 = 4'h3,
    BGF_INT_DOT_64K = 4'h4,
    BGF_INT_DOT_16M = 4'h5,
    BGF_EXT_BLK_4 = 4'h9,
    BGF_EXT_BLK_16 = 4'hA,
    BGF_EXT_BLK_256 = 4'hB,
    BGF_EXT_BLK_64K = 4'hC,
    BGF_EXT_BLK_16M = 4'hD,
    BGF_EXT_DOT_64K = 4'hE,
    BGF_EXT_DOT_16M = 4'hF
} bg_format_t;

typedef struct packed {
    bg_format_t     format;
    logic [2:0]     prio;
    logic [7:0]     bat, cg;
    logic [3:0]     size_m, size_n;
    logic [10:0]    bsx, bsy;
} rf_bgp_t;

typedef struct packed {
    logic signed [15:0] a, b, c, d; // signed fixed-point 8.8
    logic signed [15:0] x0, y0;     // transformation center
} rf_bg0at_t;

typedef struct packed {
    logic [3:0]     mpwa;
    logic [8:0]     mpwd;
    logic           mpwr;
    logic           mpsw;
    logic           kpage;
    rf_bgp_t [3:0]  bgp;
    logic           rsw;
    logic [3:0]     sub_wrap;
    logic [7:0]     sub_bat0, sub_cg0;
    logic [3:0]     size_sub_m0, size_sub_n0;
    rf_bg0at_t      bg0at;
} rf_bgm_t;

typedef struct packed {
    logic           nop;
    logic [1:0]     layer;
    logic           rotate;
    logic           bat; // BAT / -CG
    logic           ext; // EXT / -INT
    logic [2:0]     cgoff; // CG offset
} mpd_t;

//////////////////////////////////////////////////////////////////////
// HuC6271 data transfer

typedef struct packed {
    logic          ren;
    logic          rint;
    logic          kpage;
    logic          kba;
    logic [16:0]   ka; // data start addr.
    logic [8:0]    tsr; // transfer start raster
    logic [4:0]    tbc; // transfer block count
    logic [8:0]    rm; // raster monitor
} rf_c71xfer_t;

typedef struct packed {
    logic          rm_int;
} st_c71xfer_t;

//////////////////////////////////////////////////////////////////////
// HuC6230 data transfer

typedef struct packed {
    logic [2:1]     ren;
    logic [1:0]     div;
    logic [2:1]     rng;
    logic [2:1]     bend;
    logic [2:1]     bhlf;
    logic           kpage;
    logic           kba1;
    logic [16:8]    kasta1;
    logic [16:0]    kaend1;
    logic [16:6]    kahlf1;
    logic           kba2;
    logic [16:8]    kasta2;
    logic [16:0]    kaend2;
    logic [16:6]    kahlf2;

    logic           ren_ws;
    logic           reset_int;
} rf_c30xfer_t;

typedef struct packed {
    logic [2:1]     send;
    logic [2:1]     shlf;
    logic           act_int;
} st_c30xfer_t;
