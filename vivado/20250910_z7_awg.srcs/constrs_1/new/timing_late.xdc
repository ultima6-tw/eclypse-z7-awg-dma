# 這次我們不猜名字，改用「物件抓取法」，這在 Late 階段最穩
set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_ports clock_rtl]] \
    -group [get_clocks -of_objects [get_ports ext_clock_in]] \
    -group [get_clocks -filter {NAME =~ *clk_fpga_0*}] \
    -group [get_clocks -filter {NAME =~ *clk_out1_design_1_clk_wiz_1_0*}]