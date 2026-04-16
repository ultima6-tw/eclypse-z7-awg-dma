// =====================================================================
// Module: dac_master_controller (Final Symmetric Edition)
// Description:
//   1. dma_path: 脈衝觸發 (Pulse)，負責 S0/S2 <-> S1/S3 路徑切換。
//   2. dac_run:  電位維持 (Level)，負責 AXI-Stream 數據流發射。
//   3. 對稱同步: 支援 Local/Remote 雙輸入與 [1:0] 雙轉發。
// =====================================================================

module dac_master_controller (
    input  wire        clk,
    input  wire        resetn,

    // --- 模式控制 ---
    input  wire        is_master,           // 1: Master 板, 0: Slave 板

    // --- 1. DMA Path 控制 (脈衝 Pulse) ---
    input  wire        dma_path_local_in,   // 本機 GPIO 脈衝
    input  wire        dma_path_remote_in,  // 來自 PMOD 的遠端脈衝
    output wire [1:0]  dma_path_forward,    // 轉發 [1:0] 給其他板子
    output wire        current_path,        // 當前路徑狀態 (0 或 1)

    // --- 2. DAC Run 控制 (電位 Level) ---
    input  wire        dac_run_local_in,    // 本機 GPIO 電位 (維持 1 啟動)
    input  wire        dac_run_remote_in,   // 來自 PMOD 的遠端電位
    output wire [1:0]  dac_run_forward,     // 轉發 [1:0] 給其他板子

    // --- AXI-Stream Slave Ports (DMA/FIFO) ---
    input  wire [31:0] s0_axis_tdata, input wire s0_axis_tvalid, output wire s0_axis_tready,
    input  wire [31:0] s1_axis_tdata, input wire s1_axis_tvalid, output wire s1_axis_tready,
    input  wire [31:0] s2_axis_tdata, input wire s2_axis_tvalid, output wire s2_axis_tready,
    input  wire [31:0] s3_axis_tdata, input wire s3_axis_tvalid, output wire s3_axis_tready,

    // --- AXI-Stream Master Ports (Pod A & B) ---
    output wire [31:0] m_axis_a_tdata, output wire m_axis_a_tvalid, input wire m_axis_a_tready,
    output wire [31:0] m_axis_b_tdata, output wire m_axis_b_tvalid, input wire m_axis_b_tready
);

    // -----------------------------------------------------------------
    // A. 訊號同步器 (防止亞穩態，各打兩拍)
    // -----------------------------------------------------------------
    reg [1:0] sync_path_l, sync_path_r;
    reg [1:0] sync_run_l,  sync_run_r;

    always @(posedge clk) begin
        if (!resetn) begin
            sync_path_l <= 2'b0; sync_path_r <= 2'b0;
            sync_run_l  <= 2'b0; sync_run_r  <= 2'b0;
        end else begin
            sync_path_l <= {sync_path_l[0], dma_path_local_in};
            sync_path_r <= {sync_path_r[0], dma_path_remote_in};
            sync_run_l  <= {sync_run_l[0],  dac_run_local_in};
            sync_run_r  <= {sync_run_r[0],  dac_run_remote_in};
        end
    end

    // -----------------------------------------------------------------
    // B. 控制來源判定與轉發邏輯
    // -----------------------------------------------------------------
    // 選取本機實際要跟隨的訊號
    wire internal_path_sig = is_master ? sync_path_l[1] : sync_path_r[1];
    wire internal_run_sig  = is_master ? sync_run_l[1]  : sync_run_r[1];

    // 轉發邏輯：只有 Master 才將本機 GPIO 訊號扇出到 [1:0]
    assign dma_path_forward = is_master ? {sync_path_l[1], sync_path_l[1]} : 2'b00;
    assign dac_run_forward  = is_master ? {sync_run_l[1],  sync_run_l[1]}  : 2'b00;

    // -----------------------------------------------------------------
    // C. DMA Path 切換狀態機 (脈衝觸發)
    // -----------------------------------------------------------------
    reg  path_p1;
    reg  path_reg;
    always @(posedge clk) path_p1 <= internal_path_sig;
    
    // 偵測脈衝上升緣
    wire path_trigger_edge = (internal_path_sig == 1'b1 && path_p1 == 1'b0);

    always @(posedge clk) begin
        if (!resetn) path_reg <= 1'b0;
        else if (path_trigger_edge) path_reg <= !path_reg;
    end

    assign current_path = path_reg;

    // -----------------------------------------------------------------
    // D. AXI-Stream Mux + Valve (DAC Run 控制)
    // -----------------------------------------------------------------
    
    // Pod A 數據流處理
    wire [31:0] a_data_mux  = path_reg ? s1_axis_tdata  : s0_axis_tdata;
    wire        a_valid_mux = path_reg ? s1_axis_tvalid : s0_axis_tvalid;
    
    assign m_axis_a_tdata  = a_data_mux;
    // 當 dac_run 為 1 時才放行 TVALID
    assign m_axis_a_tvalid = internal_run_sig ? a_valid_mux : 1'b0;
    
    // 當 dac_run 為 1 且路徑正確時才回傳 TREADY
    assign s0_axis_tready  = (!path_reg && internal_run_sig) ? m_axis_a_tready : 1'b0;
    assign s1_axis_tready  = ( path_reg && internal_run_sig) ? m_axis_a_tready : 1'b0;

    // Pod B 數據流處理
    wire [31:0] b_data_mux  = path_reg ? s3_axis_tdata  : s2_axis_tdata;
    wire        b_valid_mux = path_reg ? s3_axis_tvalid : s2_axis_tvalid;

    assign m_axis_b_tdata  = b_data_mux;
    assign m_axis_b_tvalid = internal_run_sig ? b_valid_mux : 1'b0;

    assign s2_axis_tready  = (!path_reg && internal_run_sig) ? m_axis_b_tready : 1'b0;
    assign s3_axis_tready  = ( path_reg && internal_run_sig) ? m_axis_b_tready : 1'b0;

endmodule