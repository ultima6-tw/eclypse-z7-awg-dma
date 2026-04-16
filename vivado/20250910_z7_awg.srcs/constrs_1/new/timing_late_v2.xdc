# 1. 宣告 AXI 系統時鐘 (PS) 與 所有 PL 端生成的時鐘為非同步
# 這樣可以同時解決 FIFO、GPIO 到 DAC 的紅字，以及 GPIO 到 my_clk_mux (ref_clk) 的重置紅字
set_clock_groups -asynchronous \
    -group [get_clocks {clk_fpga_0 clk_fpga_1}] \
    -group [get_clocks {clk_out1_design_1_clk_wiz_1_0 clk_out1_design_1_clk_wiz_1_0_1 clk_out2_design_1_clk_wiz_1_0 clk_out2_design_1_clk_wiz_1_0_1 clk_out1_design_1_clk_wiz_2_0 clk_out2_design_1_clk_wiz_2_0}]
    
   # 2. 宣告這三個時鐘源為「物理互斥」(Physically Exclusive)
# 這樣 Vivado 就會知道，無論 Mux 怎麼切，這三者之間都不會有時序路徑
set_clock_groups -physically_exclusive \
    -group [get_clocks -include_generated_clocks clk_ext_10M] \
    -group [get_clocks -include_generated_clocks clk_fpga_1] \
    -group [get_clocks -include_generated_clocks clk_out1_design_1_clk_wiz_2_0]