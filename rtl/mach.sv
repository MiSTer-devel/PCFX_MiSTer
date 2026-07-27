// Computer assembly
//
// Copyright (c) 2025-2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

/* verilator lint_off PINMISSING */

import core_pkg::*;

module mach
  (
   input         CLK,
   input         CE,
   input         RESn,

   output        SDRAM_HBLANK,
   output        CPU_BCYSTn,

   output [19:0] ROM_A,
   input [15:0]  ROM_DO,
   output        ROM_CEn,
   input         ROM_READYn,

   output [20:0] RAM_A,
   output [31:0] RAM_DI,
   input [31:0]  RAM_DO,
   output        RAM_CEn,
   output        RAM_WEn,
   output [3:0]  RAM_BEn,
   input         RAM_READYn,

   output [14:0] SRAM_A,
   output [7:0]  SRAM_DI,
   input [7:0]   SRAM_DO,
   output        SRAM_CEn,
   output        SRAM_WEn,
   input         SRAM_READYn,

   output [26:1] MCP_A,
   output [7:0]  MCP_DI,
   input [7:0]   MCP_DO,
   output        MCP_CSn,
   output        MCP_RDn,
   output        MCP_WRn,
   input         MCP_READYn,

   // KRAM bank A memory interface
   output [17:0] KRAMA_A,
   input [15:0]  KRAMA_DI,
   output [15:0] KRAMA_DO,
   output [1:0]  KRAMA_BE,
   output        KRAMA_WR,
   output        KRAMA_REQ,
   input         KRAMA_ACK,

   // KRAM bank B memory interface
   output [17:0] KRAMB_A,
   input [15:0]  KRAMB_DI,
   output [15:0] KRAMB_DO,
   output [1:0]  KRAMB_BE,
   output        KRAMB_WR,
   output        KRAMB_REQ,
   input         KRAMB_ACK,

   // CD-ROM block transfer interface
   input         CD_EN,
   output [31:0] CD_SD_LBA,
   output        CD_SD_RD,
   input         CD_SD_ACK,
   output [12:0] CD_SDBUF_ADDR,
   input [15:0]  CD_SDBUF_DOUT,

   input         hmi_t HMI,

   output [31:0] A,
   output reg    ERROR,

   output        VID_PCE,
   output [7:0]  VID_Y,
   output [7:0]  VID_U,
   output [7:0]  VID_V,
   output        VID_VSn,
   output        VID_HSn,
   output        VID_VBL,
   output        VID_HBL,

   output [15:0] AUD_SLOUT,
   output [15:0] AUD_SROUT
   );

wire [31:0]     cpu_a;
logic [31:0]    cpu_d_i;
wire [31:0]     cpu_d_o;
wire [3:0]      cpu_ben;
wire [1:0]      cpu_st;
wire            cpu_dan;
wire            cpu_mrqn;
wire            cpu_rw;
wire            cpu_bcystn;
wire            cpu_readyn;
wire            cpu_szrqn;
logic           cpu_int;
logic [3:0]     cpu_intvn;
logic           cpu_nmin;

logic           rom_cen;
logic [15:0]    rom_do;
logic           rom_readyn;

logic           ram_cen;
wire [31:0]     ram_do;
logic           ram_readyn;

logic           sram_cen;
wire [7:0]      sram_do;
logic           sram_readyn;

logic           mcp_csn;
wire [7:0]      mcp_do;
logic           mcp_readyn;

logic           a1_16;
logic [31:0]    mem16_a;

logic           io_cen;
logic [15:0]    io_do;
wire [3:0]      io_int;

logic           unk_cen;

logic           vce_csn;
logic [15:0]    vce_do;

logic           vdc0_csn;
logic           vdc0_busyn;
logic           vdc0_irqn;
logic [15:0]    vdc0_do;
logic [8:0]     vdc0_vd;

wire [15:0]     vram0_a;
wire [15:0]     vram0_di, vram0_do;
wire            vram0_we;

logic           vdc1_csn;
logic           vdc1_busyn;
logic           vdc1_irqn;
logic [15:0]    vdc1_do;
logic [8:0]     vdc1_vd;

wire [15:0]     vram1_a;
wire [15:0]     vram1_di, vram1_do;
wire            vram1_we;

logic           ga_wrn, ga_rdn;
logic           ga_csn;
logic [15:0]    ga_do;
logic           vdc_cpu_ce;

logic           dck70, dck70_negedge;
logic           dckkr, dckkr_negedge;
logic           hs_posedge, hs_negedge;
logic           vs_posedge, vs_negedge;

wire            apu_csn;
wire [15:0]     apu_slout, apu_srout;

wire [15:0]     vpu_do;
wire            vpu_csn;
wire            vpu_vdmode;
wire [23:0]     vpu_vd;

wire [7:0]      kbus_di;
wire            kbus_rhnl;
wire            kbus_req_vpu, kbus_ack_vpu;
wire [1:0]      kbus_csn_c30;

wire [12:0]     rrama_a, rramb_a;
wire [7:0]      rrama_di, rrama_do, rramb_di, rramb_do;
wire            rrama_oen, rrama_wen, rramb_oen, rramb_wen;

wire            mmc_csn;
logic           mmc_busyn;
wire            mmc_irqn;
wire [15:0]     mmc_do;
wire [7:0]      mmc_scsi_do;
wire            mmc_scsi_doe;

wire            mmc_vdmode;
logic [23:0]    mmc_vd;
logic           mmc_vde;

logic [7:0]     scsi_data;
wire            scsi_atnn, scsi_bsyn, scsi_ackn, scsi_rstn,  scsi_msgn,
                scsi_seln, scsi_cdn, scsi_reqn, scsi_ion;

wire [7:0]      scsi_cd_do;
logic [7:0]     scsi_cd_status;
logic           scsi_cd_stat_get;
logic [95:0]    scsi_cd_command;
wire            scsi_cd_comm_send;
logic           scsi_cd_dout_req;
logic [79:0]    scsi_cd_dout;
logic           scsi_cd_dout_send;
logic [7:0]     scsi_cd_cd_data;
logic           scsi_cd_cd_wr;
logic           scsi_cd_cd_ready;
logic           scsi_cd_cd_data_end;
logic           scsi_cd_msgout_pend;
logic [7:0]     scsi_cd_msgout;
logic           scsi_cd_msgout_send;

wire [1:0]      kp_latch;
wire [1:0]      kp_clk;
wire [1:0]      kp_rw;
wire [1:0]      kp_din;
wire [1:0]      kp_dout;

v810 cpu
    (
     .RESn(RESn),
     .CLK(CLK),
     .CE(CE),

     .A(cpu_a),
     .D_I(cpu_d_i),
     .D_O(cpu_d_o),
     .BEn(cpu_ben),
     .ST(cpu_st),
     .DAn(cpu_dan),
     .MRQn(cpu_mrqn),
     .RW(cpu_rw),
     .BCYSTn(cpu_bcystn),
     .READYn(cpu_readyn),
     .SZRQn(cpu_szrqn),

     .INT(cpu_int),
     .INTVn(cpu_intvn),
     .NMIn(cpu_nmin)
     );

assign io_int[0] = '0; //huc6273_int;
assign io_int[1] = ~vdc1_irqn;
assign io_int[2] = ~mmc_irqn;
assign io_int[3] = ~vdc0_irqn;

fx_ga ga
    (
     .RESn(RESn),
     .CLK(CLK),
     .CE(CE),

     .A(cpu_a),
     .DI(cpu_d_o[15:0]),
     .DO(ga_do),
     .BEn(cpu_ben),
     .ST(cpu_st),
     .DAn(cpu_dan),
     .MRQn(cpu_mrqn),
     .RW(cpu_rw),
     .BCYSTn(cpu_bcystn),
     .READYn(cpu_readyn),
     .SZRQn(cpu_szrqn),

     .A1_16(a1_16),
     .ROM_CEn(rom_cen),
     .RAM_CEn(ram_cen),
     .SRAM_CEn(sram_cen),
     .MCP_CSn(mcp_csn),
     .IO_CEn(io_cen),

     .FX_GA_CSn(ga_csn),
     .APU_CSn(apu_csn),
     .VPU_CSn(vpu_csn),
     .VCE_CSn(vce_csn),
     .VDC0_CSn(vdc0_csn),
     .VDC1_CSn(vdc1_csn),
     .MMC_CSn(mmc_csn),

     .ROM_READYn(rom_readyn),
     .RAM_READYn(ram_readyn),
     .SRAM_READYn(sram_readyn),
     .MCP_READYn(mcp_readyn),

     .WRn(ga_wrn),
     .RDn(ga_rdn),
     .VDC_CPU_CE(vdc_cpu_ce),
     .VDC0_BUSYn(vdc0_busyn),
     .VDC1_BUSYn(vdc1_busyn),
     .MMC_BUSYn(mmc_busyn),

     .DINT(io_int),

     .CINT(cpu_int),
     .CINTVn(cpu_intvn),
     .CNMIn(cpu_nmin),

     .KP_LATCH(kp_latch),
     .KP_CLK(kp_clk),
     .KP_RW(kp_rw),
     .KP_DIN(kp_din),
     .KP_DOUT(kp_dout)
     );

huc6261 vce
    (
     .RESn(RESn),
     .CLK(CLK),
     .CE(CE),            // TODO: Divide .CE by 5 for 5MHz pixel clock

     .CSn(vce_csn),
     .WRn(ga_wrn),
     .RDn(ga_rdn),
     .A2(mem16_a[2]),
     .DI(cpu_d_o[15:0]),
     .DO(vce_do),

     .SDRAM_HBLANK(SDRAM_HBLANK),

     .DCK70(dck70),
     .DCK70_NEGEDGE(dck70_negedge),
     .HSYNC_POSEDGE(hs_posedge),
     .HSYNC_NEGEDGE(hs_negedge),
     .VSYNC_POSEDGE(vs_posedge),
     .VSYNC_NEGEDGE(vs_negedge),

     .VDC0_VD(vdc0_vd),
     .VDC1_VD(vdc1_vd),

     .DCKKR(dckkr),
     .DCKKR_NEGEDGE(dckkr_negedge),
     .MMC_VDMODE(mmc_vdmode),
     .MMC_VD(mmc_vd),
     .VPU_VDMODE(vpu_vdmode),
     .VPU_VD(vpu_vd),

     .Y(VID_Y),
     .U(VID_U),
     .V(VID_V),
     .VSn(VID_VSn),
     .HSn(VID_HSn),
     .VBL(VID_VBL),
     .HBL(VID_HBL)
     );

huc6270 vdc0
    (
     .CLK(CLK),
     .RST_N(RESn),
     .CLR_MEM('0),
     .CPU_CE(vdc_cpu_ce),

     .BYTEWORD('0),
     .A({mem16_a[2], 1'b0}),
     .DI(cpu_d_o[15:0]),
     .DO(vdc0_do),
     .CS_N(vdc0_csn),
     .WR_N(ga_wrn),
     .RD_N(ga_rdn),
     .BUSY_N(vdc0_busyn),
     .IRQ_N(vdc0_irqn),

     .DCK_CE(dck70),
     .DCK_CE_F(dck70_negedge),
     .HSYNC_F(hs_negedge),
     .HSYNC_R(hs_posedge),
     .VSYNC_F(vs_negedge),
     .VSYNC_R(vs_posedge),
     .VD(vdc0_vd),
     .BORDER(),
     .GRID(),
     .SP64('0),

     .RAM_A(vram0_a),
     .RAM_DI(vram0_di),
     .RAM_DO(vram0_do),
     .RAM_WE(vram0_we),

     .BG_EN('1),
     .SPR_EN('1)
     );

dpram #(.addr_width(16), .data_width(16), .disable_value(0)) vram0
    (
     .clock(CLK),
     .address_a(vram0_a),
     .data_a(vram0_do),
     .enable_a('1),
     .wren_a(vram0_we),
     .q_a(vram0_di),
     .cs_a('1),
     .address_b('0),
     .data_b('0),
     .enable_b('1),
     .wren_b('0),
     .q_b(),
     .cs_b('1)
     );

huc6270 vdc1
    (
     .CLK(CLK),
     .RST_N(RESn),
     .CLR_MEM('0),
     .CPU_CE(vdc_cpu_ce),

     .BYTEWORD('0),
     .A({mem16_a[2], 1'b0}),
     .DI(cpu_d_o[15:0]),
     .DO(vdc1_do),
     .CS_N(vdc1_csn),
     .WR_N(ga_wrn),
     .RD_N(ga_rdn),
     .BUSY_N(vdc1_busyn),
     .IRQ_N(vdc1_irqn),

     .DCK_CE(dck70),
     .DCK_CE_F(dck70_negedge),
     .HSYNC_F(hs_negedge),
     .HSYNC_R(hs_posedge),
     .VSYNC_F(vs_negedge),
     .VSYNC_R(vs_posedge),
     .VD(vdc1_vd),
     .BORDER(),
     .GRID(),
     .SP64('0),

     .RAM_A(vram1_a),
     .RAM_DI(vram1_di),
     .RAM_DO(vram1_do),
     .RAM_WE(vram1_we),

     .BG_EN('1),
     .SPR_EN('1)
     );

dpram #(.addr_width(16), .data_width(16), .disable_value(0)) vram1
    (
     .clock(CLK),
     .address_a(vram1_a),
     .data_a(vram1_do),
     .enable_a('1),
     .wren_a(vram1_we),
     .q_a(vram1_di),
     .cs_a('1),
     .address_b('0),
     .data_b('0),
     .enable_b('1),
     .wren_b('0),
     .q_b(),
     .cs_b('1)
     );

huc6271 vpu
   (
    .CLK(CLK),
    .CE(CE),
    .RESn(RESn),
    
    .A(mem16_a[4:2]),
    .DI(cpu_d_o[15:0]),
    .DO(vpu_do),
    .CSn(vpu_csn),
    .WRn(ga_wrn),
    .RDn(ga_rdn),

    .KBUS_DI(kbus_di),
    .KBUS_REQ(kbus_req_vpu),
    .KBUS_ACK(kbus_ack_vpu),

    .RA_A(rrama_a),
    .RA_DI(rrama_di),
    .RA_DO(rrama_do),
    .RA_OEn(rrama_oen),
    .RA_WEn(rrama_wen),

    .RB_A(rramb_a),
    .RB_DI(rramb_di),
    .RB_DO(rramb_do),
    .RB_OEn(rramb_oen),
    .RB_WEn(rramb_wen),

    .DCK(dckkr),
    .HSYNC_NEGEDGE(hs_negedge),
    .VDMODE(vpu_vdmode),
    .VD(vpu_vd)
    );

dpram #(.addr_width(13), .data_width(8), .disable_value(0)) rrama
    (
     .clock(CLK),
     .address_a(rrama_a),
     .data_a(rrama_do),
     .enable_a('1),
     .wren_a(~rrama_wen),
     .q_a(rrama_di),
     .cs_a(~rrama_oen | ~rrama_wen),
     .address_b('0),
     .data_b('0),
     .enable_b('1),
     .wren_b('0),
     .q_b(),
     .cs_b('1)
     );

dpram #(.addr_width(13), .data_width(8), .disable_value(0)) rramb
    (
     .clock(CLK),
     .address_a(rramb_a),
     .data_a(rramb_do),
     .enable_a('1),
     .wren_a(~rramb_wen),
     .q_a(rramb_di),
     .cs_a(~rramb_oen | ~rramb_wen),
     .address_b('0),
     .data_b('0),
     .enable_b('1),
     .wren_b('0),
     .q_b(),
     .cs_b('1)
     );

huc6272 mmc
    (
     .CLK(CLK),
     .RESn(RESn),
     .CE(CE),

     .A(mem16_a[2:1]),
     .DI(cpu_d_o[15:0]),
     .DO(mmc_do),
     .CSn(mmc_csn),
     .WRn(ga_wrn),
     .RDn(ga_rdn),
     .BUSYn(mmc_busyn),
     .IRQn(mmc_irqn),

     .MA_A(KRAMA_A),
     .MA_DI(KRAMA_DI),
     .MA_DO(KRAMA_DO),
     .MA_BE(KRAMA_BE),
     .MA_WR(KRAMA_WR),
     .MA_REQ(KRAMA_REQ),
     .MA_ACK(KRAMA_ACK),

     .MB_A(KRAMB_A),
     .MB_DI(KRAMB_DI),
     .MB_DO(KRAMB_DO),
     .MB_BE(KRAMB_BE),
     .MB_WR(KRAMB_WR),
     .MB_REQ(KRAMB_REQ),
     .MB_ACK(KRAMB_ACK),

     .DCK(dckkr),
     .DCK_NEGEDGE(dckkr_negedge),
     .HSYNC_POSEDGE(hs_posedge),
     .HSYNC_NEGEDGE(hs_negedge),
     .VSYNC_POSEDGE(vs_posedge),
     .VSYNC_NEGEDGE(vs_negedge),
     .VDMODE(mmc_vdmode),
     .VD(mmc_vd),
     .VDE(mmc_vde),

     .SCSI_DI(scsi_data),
     .SCSI_DO(mmc_scsi_do),
     .SCSI_DOE(mmc_scsi_doe),
     .SCSI_ATNn(scsi_atnn),
     .SCSI_BSYn(scsi_bsyn),
     .SCSI_ACKn(scsi_ackn),
     .SCSI_RSTn(scsi_rstn),
     .SCSI_MSGn(scsi_msgn),
     .SCSI_SELn(scsi_seln),
     .SCSI_CDn(scsi_cdn),
     .SCSI_REQn(scsi_reqn),
     .SCSI_IOn(scsi_ion),

     .KBUS_DO(kbus_di),
     .KBUS_RHnL(kbus_rhnl),
     .KBUS_REQ_C71(kbus_req_vpu),
     .KBUS_ACK_C71(kbus_ack_vpu),
     .KBUS_CSn_C30(kbus_csn_c30)
     );

huc6230 apu
   (
    .CLK(CLK),
    .RESn(RESn),
    .CE(CE),

    .A(mem16_a[5:1]),
    .DI(cpu_d_o[7:0]),
    .CSn(apu_csn),
    .WRn(ga_wrn),

    .KBUS_DI(kbus_di),
    .KBUS_RHnL(kbus_rhnl),
    .KBUS_CSn(kbus_csn_c30),

    .DCK(dckkr),
    .HSYNC_NEGEDGE(hs_negedge),

    .SLOUT(apu_slout),
    .SROUT(apu_srout)
    );

// SCSI <-> CD bridge
scsi scsi_cd
    (
     .RESET_N(RESn),
     .CLK(CLK),
     .DBI(scsi_data),
     .DBO(scsi_cd_do),
     .SEL_N(scsi_seln),
     .ACK_N(scsi_ackn),
     .RST_N(scsi_rstn),
     .ATN_N(scsi_atnn),
     .BSY_N(scsi_bsyn),
     .REQ_N(scsi_reqn),
     .MSG_N(scsi_msgn),
     .CD_N(scsi_cdn),
     .IO_N(scsi_ion),
     .STATUS(scsi_cd_status),
     .MESSAGE('0),
     .STAT_GET(scsi_cd_stat_get),
     .COMMAND(scsi_cd_command),
     .COMM_SEND(scsi_cd_comm_send),
     .DOUT_REQ(scsi_cd_dout_req),
     .DOUT(scsi_cd_dout),
     .DOUT_SEND(scsi_cd_dout_send),
     .CD_DATA(scsi_cd_cd_data),
     .CD_WR(scsi_cd_cd_wr),
     .CD_READY(scsi_cd_cd_ready),
     .CD_DATA_END(scsi_cd_cd_data_end),
     .MSGOUT_PEND(scsi_cd_msgout_pend),
     .MSGOUT(scsi_cd_msgout),
     .MSGOUT_SEND(scsi_cd_msgout_send),
     .STOP_CD_SND(),
     .DBG_DATAIN_CNT()
     );

//////////////////////////////////////////////////////////////////////
// CPU memory / I/O bus

always @* begin
    if (~rom_cen)
        cpu_d_i = {16'b0, rom_do};
    else if (~ram_cen)
        cpu_d_i = ram_do;
    else if (~sram_cen)
        cpu_d_i = {24'b0, sram_do};
    else if (~mcp_csn)
        cpu_d_i = {24'b0, mcp_do};
    else if (~io_cen)
        cpu_d_i = {16'b0, io_do};
    else
        cpu_d_i = '0;
end

always @* begin
    if (~vce_csn)
        io_do = vce_do;
    else if (~vdc0_csn)
        io_do = vdc0_do;
    else if (~vdc1_csn)
        io_do = vdc1_do;
    else if (~ga_csn)
        io_do = ga_do;
    else if (~vpu_csn)
        io_do = vpu_do;
    else if (~mmc_csn)
        io_do = mmc_do;
    else
        io_do = '0;
end

assign rom_do = ROM_DO;
assign rom_readyn = rom_cen | ROM_READYn;

assign ram_do = RAM_DO;
assign ram_readyn = ram_cen | RAM_READYn;

assign sram_do = SRAM_DO;
assign sram_readyn = sram_cen | SRAM_READYn;

assign mcp_do = MCP_DO;
assign mcp_readyn = mcp_csn | MCP_READYn;

assign mem16_a = {cpu_a[31:2], a1_16, 1'b0};

assign CPU_BCYSTn = cpu_bcystn;

//////////////////////////////////////////////////////////////////////
// Core memory interface

assign ROM_CEn = rom_cen;
assign ROM_A = mem16_a[19:0];

assign RAM_CEn = ram_cen;
assign RAM_A = cpu_a[20:0];
assign RAM_DI = cpu_d_o;
assign RAM_WEn = ram_cen | cpu_rw;
assign RAM_BEn = cpu_ben;

assign SRAM_CEn = sram_cen;
assign SRAM_A = mem16_a[15:1];
assign SRAM_DI = cpu_d_o[7:0];
assign SRAM_WEn = sram_cen | cpu_rw;

assign MCP_CSn = mcp_csn;
assign MCP_A = mem16_a[26:1];
assign MCP_DI = cpu_d_o[7:0];
assign MCP_RDn = mcp_csn | ~cpu_rw;
assign MCP_WRn = mcp_csn | cpu_rw;

//////////////////////////////////////////////////////////////////////
// SCSI interface

assign scsi_data = mmc_scsi_doe ? mmc_scsi_do : scsi_cd_do;

fake_cd fake_cd
    (
     .CLK(CLK),
     .RESn(RESn),

     .STAT_GET(scsi_cd_stat_get),
     .COMMAND(scsi_cd_command),
     .COMM_SEND(scsi_cd_comm_send),
     .STATUS(scsi_cd_status),
     .DOUT_REQ(scsi_cd_dout_req),
     .DOUT(scsi_cd_dout),
     .DOUT_SEND(scsi_cd_dout_send),
     .CD_DATA(scsi_cd_cd_data),
     .CD_WR(scsi_cd_cd_wr),
     .CD_READY(scsi_cd_cd_ready),
     .CD_DATA_END(scsi_cd_cd_data_end),
     .MSGOUT_PEND(scsi_cd_msgout_pend),
     .MSGOUT(scsi_cd_msgout),
     .MSGOUT_SEND(scsi_cd_msgout_send),

     .MEDIUM_EMPTY(~CD_EN),
     .SD_LBA(CD_SD_LBA),
     .SD_RD(CD_SD_RD),
     .SD_ACK(CD_SD_ACK),
     .SDBUF_ADDR(CD_SDBUF_ADDR),
     .SDBUF_DOUT(CD_SDBUF_DOUT)
     );

//////////////////////////////////////////////////////////////////////
// K-port interface

hmi2kp hmi2kp
    (
     .CLK(CLK),
     .RESn(RESn),

     .HMI(HMI),

     .KP_LATCH(kp_latch),
     .KP_CLK(kp_clk),
     .KP_RW(kp_rw),
     .KP_DIN(kp_din),
     .KP_DOUT(kp_dout)
     );

//////////////////////////////////////////////////////////////////////

assign A = cpu_a;
assign VID_PCE = dck70;

assign AUD_SLOUT = apu_slout;
assign AUD_SROUT = apu_srout;

//////////////////////////////////////////////////////////////////////

always @(posedge CLK) if (0 && CE) begin
    if (~io_cen & ~cpu_dan & ~cpu_readyn)
        $display("%t: %x %s %x", $realtime,A, (cpu_rw ? "R" : "w"), 
                 (cpu_rw ? cpu_d_i[15:0] : cpu_d_o[15:0]));
end

always @(posedge CLK) if (1 && CE) begin
    if (~RESn) begin
        ERROR <= '0;
    end
    else begin
        if (~cpu_bcystn & ~cpu_mrqn &
            ((cpu_a == 32'hFFFFFF90) | (cpu_a == 32'hFFFFFFD0)))
            ERROR <= '1;
    end
end

always @(posedge ERROR)
    $finish(1);

endmodule
