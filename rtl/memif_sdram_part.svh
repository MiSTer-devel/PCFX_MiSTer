// SDRAM partitions
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

// The PC-FX has several discrete DRAM memories and controllers.  Each
// memory is allocated to a different SDRAM bank to take advantage of
// interleaved access, allowing us to access them near-simultaneously.

// Bank 0: Memory directly addressable by the CPU
localparam [26:0] ROM_BASE_A   = 27'h000_0000; // ..00F_FFFF
localparam [26:0] RAM_BASE_A   = 27'h010_0000; // ..02F_FFFF
localparam [26:0] SRAM_BASE_A  = 27'h040_0000; // ..040_7FFF
localparam [26:0] BMP_BASE_A   = 27'h080_0000; // ..0FF_FFFF

// Bank 1: KING RAM A
localparam [26:0] KRAMA_BASE_A = 27'h100_0000; // ..107_FFFF

// Bank 2: KING RAM B
localparam [26:0] KRAMB_BASE_A = 27'h200_0000; // ..207_FFFF
