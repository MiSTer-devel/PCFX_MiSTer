// HuC6272 (KING) debug support
//
// Copyright (c) 2026 David Hunter
//
// This program is GPL licensed. See COPYING for the full license.

task dump_regs();
    $display("HuC6272 register dump");
    $display("  KING BG:  10=%x 12=%x 16=%x",
             {rf_bgm.bgp[3].format, rf_bgm.bgp[2].format, rf_bgm.bgp[1].format, rf_bgm.bgp[0].format}, 
             {1'b0, rf_bgm.bgp[3].prio, 1'b0, rf_bgm.bgp[2].prio, 1'b0, rf_bgm.bgp[1].prio, 1'b0, rf_bgm.bgp[0].prio}, 
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
    $display("  RAINBOW:  41=%x 42=%x 43=%x 44=%x 40=%x",
             {14'b0, rf_c71xfer.kba, rf_c71xfer.ka},
             {8'b0, rf_c71xfer.tsr},
             {12'b0, rf_c71xfer.tbc},
             {8'b0, rf_c71xfer.rm},
             {14'b0, rf_c71xfer.ren, rf_c71xfer.rint});
    $display("  MPROG:    14=%x %x %x %x %x %x %x %x  %x %x %x %x %x %x %x %x",
             video.mpd[0][0], video.mpd[0][1], video.mpd[0][2], video.mpd[0][3],
             video.mpd[0][4], video.mpd[0][5], video.mpd[0][6], video.mpd[0][7],
             video.mpd[1][0], video.mpd[1][1], video.mpd[1][2], video.mpd[1][3],
             video.mpd[1][4], video.mpd[1][5], video.mpd[1][6], video.mpd[1][7]);

endtask
