# This works around a Verilator bug that fails to add .a to the link
# target dependencies in V*.mk.

include Vpcfx_top_tb.mk

Vpcfx_top_tb: ../mister_main/bin/MiSTer.a
