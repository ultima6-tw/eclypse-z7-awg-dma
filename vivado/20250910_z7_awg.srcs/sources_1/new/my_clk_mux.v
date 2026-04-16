`timescale 1ns / 1ps

module my_clk_mux (
    input  wire ref_clk,          // 125MHz 基準時鐘
    input  wire rst_n,            // 來自 GPIO 的全局重置 (Active Low)
    
    // 時鐘輸入
    input  wire clk_in0,          // 內部產出的 10MHz (Local / 來自 clk_wiz_2)
    input  wire clk_in1,          // 來自物理引腳的 10MHz (Remote/External)
    
    // 控制與狀態
    input  wire is_master,        // 1: Master(發送), 0: Remote(靜默)
    input  wire wiz_locked_in,    // 下游 MMCM 的 Locked 狀態
    input  wire upstream_locked,  // 【新增】上游 MMCM (clk_wiz_2) 的 Locked 狀態
    
    // 輸出
    output wire clk_out,          // 輸出給下游 MMCM
    output reg  wiz_rst_out,      // 下游 MMCM 的 Reset (Active Low)
    
    // 【合併】轉發輸出 (透過 ODDR 打到實體引腳)
    output wire [1:0] clk_fwd_out 
);

    // -------------------------------------------------------------------------
    // 1. 異步切換器 (處理給下游 DAC 使用的時鐘)
    // -------------------------------------------------------------------------
    BUFGMUX #(
       .CLK_SEL_TYPE("ASYNC")
    ) BUFGMUX_inst (
       .O(clk_out),
       .I0(clk_in1),    // S=0 (Remote)
       .I1(clk_in0),    // S=1 (Master)
       .S(is_master)
    );

    // -------------------------------------------------------------------------
    // 2. 狀態同步與切換偵測
    // -------------------------------------------------------------------------
    reg [1:0] master_sync;
    reg       master_delayed;
    reg [15:0] rst_counter;

    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            master_sync    <= 2'b00;
            master_delayed <= 1'b0;
        end else begin
            master_sync    <= {master_sync[0], is_master};
            master_delayed <= master_sync[1];
        end
    end

    wire mode_changed = master_sync[1] ^ master_delayed;

    // -------------------------------------------------------------------------
    // 3. 重置狀態機 (全 Active-Low 邏輯)
    // -------------------------------------------------------------------------
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            wiz_rst_out <= 1'b0;       // 0 代表把下游壓在重置狀態
            rst_counter <= 16'hFFFF; 
        end else if (mode_changed) begin
            wiz_rst_out <= 1'b0;       // 模式切換時，拉低重置
            rst_counter <= 16'hFFFF;
        end else if (rst_counter > 0) begin
            rst_counter <= rst_counter - 1'b1;
            wiz_rst_out <= 1'b0;       // 倒數期間，維持拉低重置
        end else begin
            wiz_rst_out <= 1'b1;       // 倒數結束，拉高(1)讓下游開始運作
        end
    end

    // -------------------------------------------------------------------------
    // 4. 安全保護與 ODDR 轉發輸出
    // -------------------------------------------------------------------------
    // 綜合安全閘門 (forward_en)
    // 1. rst_n == 1        (系統已啟動)
    // 2. master_sync[1]==1 (身分為 Master)
    // 3. wiz_rst_out == 1  (內部狀態機穩定)
    wire forward_en;
    assign forward_en = (rst_n == 1'b1) && (master_sync[1] == 1'b1) && (wiz_rst_out == 1'b1);

    wire clk_10mhz_gated;
    
    // 4-1. 使用 BUFGCE 確保時鐘閘控乾淨無毛刺 (消除 LUT 警告)
    BUFGCE #(
       .SIM_DEVICE("7SERIES")
    ) BUFGCE_inst (
       .O(clk_10mhz_gated),  // 內部乾淨的 10MHz 
       .CE(forward_en),      // 條件滿足時才放行
       .I(clk_in0)           
    );

    // 4-2. 使用 ODDR 將時鐘安全地輸出到實體引腳
    genvar i;
    generate
        for (i = 0; i < 2; i = i + 1) begin : gen_oddr
            ODDR #(
                .DDR_CLK_EDGE("OPPOSITE_EDGE"), 
                .INIT(1'b0),                    
                .SRTYPE("SYNC")                 
            ) ODDR_inst (
                .Q(clk_fwd_out[i]),    
                .C(clk_10mhz_gated),   // 吃經過 BUFGCE 閘控的乾淨時鐘
                .CE(1'b1),         
                .D1(1'b1),         
                .D2(1'b0),         
                
                // 雙重保護 Reset 邏輯：
                // 如果不是 Master (forward_en == 0) 或 上游時鐘不穩，強制將引腳拉低至 0
                .R(~forward_en | ~upstream_locked),   
                
                .S(1'b0)            
            );
        end
    endgenerate

endmodule