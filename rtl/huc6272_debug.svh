// HuC6272 (KING) debug support
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

task dump_regs();
    $display("HuC6272 register dump");
    $display("  Status:   %x %x %x %x",
             8'b0,
             st_scsi.cur_bus_stat,
             cpuif.isr,
             cpuif.rsel);
    $display("  SCSI:     00R=%x 00W=%x 01=%x 02=%x 03=%x 04=%x 05=%x 06=%x ",
             st_scsi.din, rf_scsi.dout,
             {rf_scsi.assert_rst, 2'b0, rf_scsi.assert_ack, rf_scsi.assert_sel, rf_scsi.assert_atn, rf_scsi.assert_data},
             {7'b0, rf_scsi.dma_mode},
             {5'b0, rf_scsi.assert_msg, rf_scsi.assert_cd, rf_scsi.assert_io},
             st_scsi.cur_bus_stat,
             {st_scsi.dma_req, 1'b0, st_scsi.int_req_act, st_scsi.phase_match, 1'b0, st_scsi.atn, st_scsi.ack},
             st_scsi.rxbuf);
    $display("            09=%x 0a=%x 0bR=%x 0bW=%x",
             {rf_scsi.dma_kba, rf_scsi.dma_ka},
             {rf_scsi.dma_byte_cnt, 1'b0},
             {7'b0, st_scsi.dma_end},
             {6'b0, rf_scsi.dma_int_en, rf_scsi.dma_en});
    $display("  KING BG:  10=%x 12=%x 16=%x",
             {rf_bgm.bgp[3].format, rf_bgm.bgp[2].format, rf_bgm.bgp[1].format, rf_bgm.bgp[0].format}, 
             {3'b0, rf_bgm.rsw, rf_bgm.bgp[3].prio, rf_bgm.bgp[2].prio, rf_bgm.bgp[1].prio, rf_bgm.bgp[0].prio}, 
             {12'b0, rf_bgm.sub_wrap});
    $display("  KBG0:     2c=%x 20=%x 21=%x 22=%x 23=%x 30=%x 31=%x",
             {rf_bgm.size_sub_n0, rf_bgm.size_sub_m0, rf_bgm.bgp[0].size_n, rf_bgm.bgp[0].size_m},
             {8'b0, rf_bgm.bgp[0].bat},
             {8'b0, rf_bgm.bgp[0].cg},
             {8'b0, rf_bgm.sub_bat0},
             {8'b0, rf_bgm.sub_cg0},
             {5'b0, rf_bgm.bgp[0].bsx},
             {5'b0, rf_bgm.bgp[0].bsy});
    $display("  KBG1:     2d=%x 24=%x 25=%x 32=%x 33=%x",
             {8'b0, rf_bgm.bgp[1].size_n, rf_bgm.bgp[1].size_m},
             {8'b0, rf_bgm.bgp[1].bat},
             {8'b0, rf_bgm.bgp[1].cg},
             {5'b0, rf_bgm.bgp[1].bsx},
             {5'b0, rf_bgm.bgp[1].bsy});
    $display("  KBG2:     2e=%x 28=%x 29=%x 34=%x 35=%x",
             {8'b0, rf_bgm.bgp[2].size_n, rf_bgm.bgp[2].size_m},
             {8'b0, rf_bgm.bgp[2].bat},
             {8'b0, rf_bgm.bgp[2].cg},
             {5'b0, rf_bgm.bgp[2].bsx},
             {5'b0, rf_bgm.bgp[2].bsy});
    $display("  KBG3:     2f=%x 2a=%x 2b=%x 36=%x 37=%x",
             {8'b0, rf_bgm.bgp[3].size_n, rf_bgm.bgp[3].size_m},
             {8'b0, rf_bgm.bgp[3].bat},
             {8'b0, rf_bgm.bgp[3].cg},
             {5'b0, rf_bgm.bgp[3].bsx},
             {5'b0, rf_bgm.bgp[3].bsy});
    $display("  RAINBOW:  40=%x 41=%x 42=%x 43=%x 44=%x",
             {14'b0, rf_c71xfer.ren, rf_c71xfer.rint},
             {14'b0, rf_c71xfer.kba, rf_c71xfer.ka},
             {8'b0, rf_c71xfer.tsr},
             {12'b0, rf_c71xfer.tbc},
             {8'b0, rf_c71xfer.rm});
    $display("  SOUNDBOX: 50=%x 51=%x 52=%x 53=%x  58=%x 59=%x 5a=%x  5b=%x 5c=%x 5d=%x",
             {rf_c30xfer.div, rf_c30xfer.ren},
             {rf_c30xfer.bhlf[1], rf_c30xfer.bend[1], rf_c30xfer.rng[1]},
             {rf_c30xfer.bhlf[2], rf_c30xfer.bend[2], rf_c30xfer.rng[2]},
             {st_c30xfer.shlf[2], st_c30xfer.send[2], st_c30xfer.shlf[1], st_c30xfer.send[1]},
             {rf_c30xfer.kba1, rf_c30xfer.kasta1},
             rf_c30xfer.kaend1,
             rf_c30xfer.kahlf1,
             {rf_c30xfer.kba2, rf_c30xfer.kasta2},
             rf_c30xfer.kaend2,
             rf_c30xfer.kahlf2);
    $display("  MPROG:    14=%x %x %x %x %x %x %x %x  %x %x %x %x %x %x %x %x",
             video.mpd[0][0], video.mpd[0][1], video.mpd[0][2], video.mpd[0][3],
             video.mpd[0][4], video.mpd[0][5], video.mpd[0][6], video.mpd[0][7],
             video.mpd[1][0], video.mpd[1][1], video.mpd[1][2], video.mpd[1][3],
             video.mpd[1][4], video.mpd[1][5], video.mpd[1][6], video.mpd[1][7]);

endtask
