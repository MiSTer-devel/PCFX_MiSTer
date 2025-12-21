// SDRAM board (dual-chip) for MiSTer
//
// Copyright (c) 2025 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

module sdram_xsds
  (
   inout [15:0] SDRAM_DQ, // 16 bit bidirectional data bus
   input [12:0] SDRAM_A, // 13 bit multiplexed address bus
   input        SDRAM_DQML, // byte mask
   input        SDRAM_DQMH, // byte mask
   input [1:0]  SDRAM_BA, // two banks
   input        SDRAM_nCS, // a single chip select
   input        SDRAM_nWE, // write enable
   input        SDRAM_nRAS, // row address select
   input        SDRAM_nCAS, // columns address select
   input        SDRAM_CLK,
   input        SDRAM_CKE
   );

as4c32m16sb u1a
  (
   .DQ(SDRAM_DQ),
   .A(SDRAM_A),
   .DQML(SDRAM_A[11]),
   .DQMH(SDRAM_A[12]),
   .BA(SDRAM_BA),
   .nCS(SDRAM_nCS),
   .nWE(SDRAM_nWE),
   .nRAS(SDRAM_nRAS),
   .nCAS(SDRAM_nCAS),
   .CLK(SDRAM_CLK),
   .CKE(SDRAM_CKE)
   );

as4c32m16sb u2a
  (
   .DQ(SDRAM_DQ),
   .A(SDRAM_A),
   .DQML(SDRAM_A[11]),
   .DQMH(SDRAM_A[12]),
   .BA(SDRAM_BA),
   .nCS(~SDRAM_nCS),
   .nWE(SDRAM_nWE),
   .nRAS(SDRAM_nRAS),
   .nCAS(SDRAM_nCAS),
   .CLK(SDRAM_CLK),
   .CKE(SDRAM_CKE)
   );

endmodule
