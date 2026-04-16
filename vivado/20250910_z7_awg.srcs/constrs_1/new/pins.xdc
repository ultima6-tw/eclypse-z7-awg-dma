set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hier -filter {NAME =~ *ext_clock_in_IBUF*}]
set_property IOSTANDARD LVCMOS33 [get_ports {clk_10M_out[*]}]
set_property SLEW SLOW [get_ports {clk_10M_out[*]}]
set_property DRIVE 4 [get_ports {clk_10M_out[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dma_trigger_out[*]}]
set_property SLEW SLOW [get_ports {dma_trigger_out[*]}]
set_property DRIVE 4 [get_ports {dma_trigger_out[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_trigger_out[*]}]
set_property SLEW SLOW [get_ports {dac_trigger_out[*]}]
set_property DRIVE 4 [get_ports {dac_trigger_out[*]}]
set_property IOB TRUE [get_cells -hier -filter {NAME =~ *ZmodAWGController*InstDataODDR*}]
set_property IOSTANDARD LVCMOS18 [get_ports {dZmodDAC_Data_0[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dZmodDAC_Data_1[*]}]
set_property SLEW SLOW [get_ports {dZmodDAC_Data_0[*]}]
set_property SLEW SLOW [get_ports {dZmodDAC_Data_1[*]}]
set_property PACKAGE_PIN M19 [get_ports ZmodDAC_ClkIO_0]
set_property IOSTANDARD LVCMOS18 [get_ports ZmodDAC_ClkIO_0]
set_property PACKAGE_PIN N19 [get_ports ZmodDAC_ClkIn_0]
set_property PACKAGE_PIN J18 [get_ports sZmodDAC_EnOut_0]
set_property PACKAGE_PIN R18 [get_ports sZmodDAC_Reset_0]
set_property PACKAGE_PIN T18 [get_ports sZmodDAC_SCLK_0]
set_property PACKAGE_PIN P16 [get_ports sZmodDAC_SDIO_0]
set_property PACKAGE_PIN T16 [get_ports sZmodDAC_SetFS1_0]
set_property PACKAGE_PIN T17 [get_ports sZmodDAC_SetFS2_0]
set_property PACKAGE_PIN R19 [get_ports {dZmodDAC_Data_0[13]}]
set_property PACKAGE_PIN R16 [get_ports sZmodDAC_CS_0]
set_property PACKAGE_PIN T19 [get_ports {dZmodDAC_Data_0[12]}]
set_property PACKAGE_PIN P17 [get_ports {dZmodDAC_Data_0[11]}]
set_property PACKAGE_PIN P18 [get_ports {dZmodDAC_Data_0[10]}]
set_property PACKAGE_PIN N15 [get_ports {dZmodDAC_Data_0[9]}]
set_property PACKAGE_PIN P15 [get_ports {dZmodDAC_Data_0[8]}]
set_property PACKAGE_PIN J20 [get_ports {dZmodDAC_Data_0[7]}]
set_property PACKAGE_PIN K21 [get_ports {dZmodDAC_Data_0[6]}]
set_property PACKAGE_PIN K20 [get_ports {dZmodDAC_Data_0[5]}]
set_property PACKAGE_PIN L19 [get_ports {dZmodDAC_Data_0[4]}]
set_property PACKAGE_PIN K18 [get_ports {dZmodDAC_Data_0[3]}]
set_property PACKAGE_PIN L22 [get_ports {dZmodDAC_Data_0[2]}]
set_property PACKAGE_PIN L18 [get_ports {dZmodDAC_Data_0[1]}]
set_property PACKAGE_PIN K19 [get_ports {dZmodDAC_Data_0[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SetFS2_0]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SetFS1_0]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SCLK_0]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_Reset_0]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_EnOut_0]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_CS_0]
set_property IOSTANDARD LVCMOS18 [get_ports ZmodDAC_ClkIn_0]

set_property PACKAGE_PIN W17 [get_ports ZmodDAC_ClkIO_1]
set_property PACKAGE_PIN W16 [get_ports ZmodDAC_ClkIn_1]
set_property PACKAGE_PIN Y18 [get_ports {dZmodDAC_Data_1[1]}]
set_property PACKAGE_PIN Y19 [get_ports {dZmodDAC_Data_1[0]}]
set_property PACKAGE_PIN AB22 [get_ports {dZmodDAC_Data_1[2]}]
set_property PACKAGE_PIN AB20 [get_ports {dZmodDAC_Data_1[3]}]
set_property PACKAGE_PIN AA18 [get_ports {dZmodDAC_Data_1[4]}]
set_property PACKAGE_PIN AA19 [get_ports {dZmodDAC_Data_1[5]}]
set_property PACKAGE_PIN Y21 [get_ports {dZmodDAC_Data_1[6]}]
set_property PACKAGE_PIN Y20 [get_ports {dZmodDAC_Data_1[7]}]
set_property PACKAGE_PIN V15 [get_ports {dZmodDAC_Data_1[8]}]
set_property PACKAGE_PIN V14 [get_ports {dZmodDAC_Data_1[9]}]
set_property PACKAGE_PIN AB15 [get_ports {dZmodDAC_Data_1[10]}]
set_property PACKAGE_PIN AB14 [get_ports {dZmodDAC_Data_1[11]}]
set_property PACKAGE_PIN W13 [get_ports {dZmodDAC_Data_1[12]}]
set_property PACKAGE_PIN V13 [get_ports {dZmodDAC_Data_1[13]}]
set_property PACKAGE_PIN Y15 [get_ports sZmodDAC_SetFS2_1]
set_property PACKAGE_PIN W15 [get_ports sZmodDAC_SetFS1_1]
set_property PACKAGE_PIN Y14 [get_ports sZmodDAC_SDIO_1]
set_property PACKAGE_PIN AA13 [get_ports sZmodDAC_SCLK_1]
set_property PACKAGE_PIN AA22 [get_ports sZmodDAC_EnOut_1]
set_property PACKAGE_PIN AA14 [get_ports sZmodDAC_CS_1]
set_property PACKAGE_PIN Y13 [get_ports sZmodDAC_Reset_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SCLK_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_EnOut_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_CS_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_Reset_1]
set_property IOSTANDARD LVCMOS18 [get_ports ZmodDAC_ClkIn_1]
set_property IOSTANDARD LVCMOS18 [get_ports ZmodDAC_ClkIO_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SetFS1_1]
set_property IOSTANDARD LVCMOS18 [get_ports sZmodDAC_SetFS2_1]


# =============================================================================
# 1. 外部時鐘輸入與時序定義 (Slave 模式使用)
# =============================================================================
# 外部 10MHz 參考時鐘輸入 (G15)
set_property PACKAGE_PIN G15 [get_ports ext_clock_in]
set_property IOSTANDARD LVCMOS33 [get_ports ext_clock_in]
set_property PULLTYPE PULLDOWN [get_ports ext_clock_in]

# 定義外部 10MHz 時鐘約束 (週期 100ns)
create_clock -period 100.000 -name clk_ext_10M [get_ports ext_clock_in]

# =============================================================================
# 2. 外部觸發輸入 (Slave 模式使用)
# =============================================================================
# DMA 觸發輸入 (D16)
set_property PACKAGE_PIN D16 [get_ports dma_trigger_in]
set_property IOSTANDARD LVCMOS33 [get_ports dma_trigger_in]
set_property PULLTYPE PULLDOWN [get_ports dma_trigger_in]

# DAC 觸發輸入 (D17)
set_property PACKAGE_PIN D17 [get_ports dac_trigger_in]
set_property IOSTANDARD LVCMOS33 [get_ports dac_trigger_in]
set_property PULLTYPE PULLDOWN [get_ports dac_trigger_in]

# =============================================================================
# 3. 輸出轉發腳位定義 (Master 模式使用 - 2 組輸出)
# =============================================================================

# --- 10MHz 時鐘轉發 (clk_10M_out[1:0]) ---
set_property PACKAGE_PIN B15 [get_ports {clk_10M_out[0]}]
set_property PACKAGE_PIN E15 [get_ports {clk_10M_out[1]}]

# --- DMA 觸發轉發 (dma_trigger_out[1:0]) ---
set_property PACKAGE_PIN C15 [get_ports {dma_trigger_out[0]}]
set_property PACKAGE_PIN F17 [get_ports {dma_trigger_out[1]}]

# --- DAC 觸發轉發 (dac_trigger_out[1:0]) ---
set_property PACKAGE_PIN D15 [get_ports {dac_trigger_out[0]}]
set_property PACKAGE_PIN F16 [get_ports {dac_trigger_out[1]}]

# 告訴 Vivado 這些輸入是非同步的，不用分析 Setup/Hold Time
set_false_path -from [get_ports dma_trigger_in]
set_false_path -from [get_ports dac_trigger_in]

# 針對轉發出去的觸發訊號設為 False Path
set_false_path -to [get_ports {dma_trigger_out[*]}]
set_false_path -to [get_ports {dac_trigger_out[*]}]

# 設定所有 DAC 數據線與控制線 (Data 0 & Data 1)
set_false_path -from [get_ports sZmodDAC_SDIO_*]
set_false_path -to [get_ports sZmodDAC_SDIO_*]
# 將剩下的低速控制線也排除在時序分析外

set_false_path -to [get_ports sZmodDAC_SCLK_*]
set_false_path -to [get_ports sZmodDAC_SDIO_*]
set_false_path -to [get_ports sZmodDAC_CS_*]

# (此處省略你原本列出的所有特定腳位 PACKAGE_PIN 定義，請保持原樣即可)

# =============================================================================
# 5. GPIO 控制訊號 CDC 精確處理
# =============================================================================
# 戰略 A：靜態係數無視時序
set_false_path -from [get_cells -hierarchical -filter {NAME =~ *axi_gpio_*coeff*/*Data_Out_reg*}]

# 戰略 B：觸發訊號放寬佈線限制 (10ns 緩衝)
set_max_delay -datapath_only -from [get_cells -hierarchical -filter {NAME =~ *axi_gpio_*_trigger*/*Data_Out_reg*}] 10.000

# ----------------------------------------------------------------------------
# RGB LED - LD2 (全部 3 色)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN A19 [get_ports {led_src_r[0]}]
set_property PACKAGE_PIN A18 [get_ports {led_src_g[0]}]
set_property PACKAGE_PIN A16 [get_ports {led_src_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_src_r[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_src_g[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_src_b[0]}]

# ----------------------------------------------------------------------------
# RGB LED - LD3 (全部 3 色)
# ----------------------------------------------------------------------------
set_property PACKAGE_PIN B17 [get_ports {led_locked_r[0]}]
set_property PACKAGE_PIN B16 [get_ports {led_locked_g[0]}]
set_property PACKAGE_PIN A17 [get_ports {led_locked_b[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_locked_r[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_locked_g[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_locked_b[0]}]

set_false_path -to [get_ports led_src_*]


# 針對 Reset 同步器放寬要求
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *InstDacSysReset*SyncAsync*/oSyncStages_reg[0]}] -to [get_cells -hier -filter {NAME =~ *InstDacSysReset*SyncAsync*/oSyncStages_reg[1]}] 8.000

# 允許 clk_wiz_2 到 my_clk_mux 之間的 BUFG-BUFG 級聯走非最佳化路由
# 因為是 10MHz 的低速時鐘，繞線延遲對系統完全無影響
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets design_1_i/clk_wiz_2/inst/clk_out1]

# 忽略從 125MHz 狀態機 (ref_clk) 到 10MHz (clk_in0) 閘控元件的靜態控制訊號時序
# 因為這些是軟體觸發的緩慢切換訊號，不需要滿足 2ns 的嚴苛 Setup Time
set_false_path -from [get_clocks clk_out2_design_1_clk_wiz_2_0] -to [get_clocks clk_out1_design_1_clk_wiz_2_0]

# 強制忽略 GPIO 選取線的時序 (False Path)
# 既然是用 0x81240000 動態切換，這條線的延遲絕對不能被當作時序分析對象
set_false_path -from [get_cells -hierarchical *axi_gpio_clock_select*]