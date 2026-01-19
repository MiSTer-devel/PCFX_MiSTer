// SDRAM partitions
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

localparam [24:0] ROM_BASE_A  = 25'h000_0000; // ..00F_FFFF
localparam [24:0] RAM_BASE_A  = 25'h010_0000; // ..02F_FFFF
localparam [24:0] SRAM_BASE_A = 25'h080_0000; // ..080_7FFF
localparam [24:0] BMP_BASE_A  = 25'h100_0000; // ..17F_FFFF
