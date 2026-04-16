# 1. 定義時鐘群組 (使用 quiet 模式確保物件不存在時也不會噴紅字報錯)

# 群組 A: PS 處理器端時鐘 (包含控制 GPIO 的 fpga_1 和 fpga_0)
set g_ps [get_clocks -quiet {clk_fpga_0 clk_fpga_1}]

# 群組 B: PL 邏輯端與外部時鐘 (包含引發 Path 162 違例的 wiz_2_out2)
set g_pl [get_clocks -quiet {
    clock_rtl 
    clk_ext_10M 
    clk_out1_design_1_clk_wiz_1_0 
    clk_out2_design_1_clk_wiz_2_0
}]

# 2. 執行隔離
# 只有當兩組時鐘都至少抓到一個物件時，才執行 Asynchronous 隔離
if { [llength $g_ps] > 0 && [llength $g_pl] > 0 } {
    set_clock_groups -asynchronous -group $g_ps -group $g_pl
    puts "CDC_FIX: [llength $g_ps] PS clocks isolated from [llength $g_pl] PL clocks."
} else {
    puts "CDC_FIX_WARNING: One or more clock groups are empty, isolation not applied."
}