// =====================================================================
// Module: dac_master_controller (Ultimate Simple Version)
// Description: 
//   1. 8 路獨立重置 (DMA x4, FIFO x4)
//   2. 脈衝觸發翻轉：偵測上升緣 (0->1) 自動切換路徑 0/1。
//   3. 身份識別：Master 轉發觸發，Slave 接收觸發。
//   4. 軟體鎖定：sw_force_reset 用於波形裝填前的清潔。
// =====================================================================

module dac_master_controller (
    input  wire        clk,
    input  wire        periph_resetn,   // 系統全局重置 (Low Active)

    // --- 觸發系統 (僅需脈衝) ---
    input  wire        is_master_mode,  // 1: Master, 0: Slave
    input  wire        sw_trigger_in,   // 軟體噴一個脈衝 (0->1->0)
    input  wire        hw_trigger,      // 實體 PMOD 脈衝
    output wire [1:0]  trigger_out,     // 轉發給其他 Slave 的訊號
    
    // --- 軟體鎖定 (4 bits) ---
    input  wire [3:0]  sw_force_reset,  // 1 為鎖定, 0 為放開

    // --- 8 根獨立硬體重置線 ---
    output wire dma_aresetn_0, output wire dma_aresetn_1,
    output wire dma_aresetn_2, output wire dma_aresetn_3,
    output wire fifo_aresetn_0, output wire fifo_aresetn_1,
    output wire fifo_aresetn_2, output wire fifo_aresetn_3,

    // --- AXI-Stream S0~S3 (來自 FIFO 0~3) ---
    input  wire [31:0] s0_axis_tdata, input wire s0_axis_tvalid, output wire s0_axis_tready,
    input  wire [31:0] s1_axis_tdata, input wire s1_axis_tvalid, output wire s1_axis_tready,
    input  wire [31:0] s2_axis_tdata, input wire s2_axis_tvalid, output wire s2_axis_tready,
    input  wire [31:0] s3_axis_tdata, input wire s3_axis_tvalid, output wire s3_axis_tready,

    // --- AXI-Stream M_A/M_B ---
    output wire [31:0] m_axis_a_tdata, output wire m_axis_a_tvalid, input wire m_axis_a_tready,
    output wire [31:0] m_axis_b_tdata, output wire m_axis_b_tvalid, input wire m_axis_b_tready
);

    // -----------------------------------------------------------------
    // 1. 脈衝觸發與狀態翻轉 (Toggle)
    // -----------------------------------------------------------------
    wire current_trig = is_master_mode ? sw_trigger_in : hw_trigger;
    // 這樣改：Master 傳出軟體訊號，Slave 則轉發它收到的硬體訊號
    assign trigger_out = is_master_mode ? {sw_trigger_in, sw_trigger_in} : 2'b00;

    reg t0, t1, t2;
    always @(posedge clk) begin
        t0 <= current_trig;
        t1 <= t0;
        t2 <= t1;
    end
    wire edge_detect = (t1 == 1'b1 && t2 == 1'b0); // 偵測上升緣

    reg toggle_path;
    always @(posedge clk) begin
        if (!periph_resetn) begin
            toggle_path <= 1'b0; // 系統啟動，強制回到路徑 0 (安全位置)
        end else if (edge_detect) begin
            toggle_path <= !toggle_path; // 每次脈衝「咔嗒」一聲就換邊
        end
    end

    // Mux 選擇訊號直接等於翻轉狀態
    wire sel_a = toggle_path;
    wire sel_b = toggle_path;

    // -----------------------------------------------------------------
    // 2. 自動清理偵測 (Edge Detection)
    // -----------------------------------------------------------------
    reg last_sel;
    reg [3:0] auto_reset_trig;

    always @(posedge clk) begin
        if (!periph_resetn) begin
            last_sel <= 0;
            auto_reset_trig <= 4'b0000;
        end else begin
            last_sel <= toggle_path;
            // 當 toggle_path 改變，觸發對應的退休路徑重置
            auto_reset_trig[0] <= (last_sel == 1'b0 && toggle_path == 1'b1); // L0 退休
            auto_reset_trig[1] <= (last_sel == 1'b1 && toggle_path == 1'b0); // L1 退休
            auto_reset_trig[2] <= (last_sel == 1'b0 && toggle_path == 1'b1); // L2 退休
            auto_reset_trig[3] <= (last_sel == 1'b1 && toggle_path == 1'b0); // L3 退休
        end
    end

    // -----------------------------------------------------------------
    // 3. 綜合重置管理與映射 (同前，但更簡潔)
    // -----------------------------------------------------------------
    reg [3:0] dma_rst_reg, fifo_rst_reg;
    reg [7:0] rst_cnt [3:0];
    integer i;

    assign {dma_aresetn_3, dma_aresetn_2, dma_aresetn_1, dma_aresetn_0} = dma_rst_reg;
    assign {fifo_aresetn_3, fifo_aresetn_2, fifo_aresetn_1, fifo_aresetn_0} = fifo_rst_reg;

    always @(posedge clk) begin
        if (!periph_resetn) begin
            dma_rst_reg <= 4'b0000; fifo_rst_reg <= 4'b0000;
            for (i=0; i<4; i=i+1) rst_cnt[i] <= 0;
        end else begin
            for (i=0; i<4; i=i+1) begin
                if (auto_reset_trig[i]) rst_cnt[i] <= 8'd64;
                if ((rst_cnt[i] > 0) || (sw_force_reset[i])) begin
                    dma_rst_reg[i]  <= 1'b0;
                    fifo_rst_reg[i] <= 1'b0;
                    if (rst_cnt[i] > 0) rst_cnt[i] <= rst_cnt[i] - 1;
                end else begin
                    dma_rst_reg[i]  <= 1'b1;
                    fifo_rst_reg[i] <= 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------------------
    // 4. AXI-Stream 數據通道 Mux (與之前一致)
    // -----------------------------------------------------------------
    assign m_axis_a_tdata  = sel_a ? s1_axis_tdata : s0_axis_tdata;
    assign m_axis_a_tvalid = sel_a ? s1_axis_tvalid : s0_axis_tvalid;
    assign s0_axis_tready  = sel_a ? 1'b0 : m_axis_a_tready;
    assign s1_axis_tready  = sel_a ? m_axis_a_tready : 1'b0;

    assign m_axis_b_tdata  = sel_b ? s3_axis_tdata : s2_axis_tdata;
    assign m_axis_b_tvalid = sel_b ? s3_axis_tvalid : s2_axis_tvalid;
    assign s2_axis_tready  = sel_b ? 1'b0 : m_axis_b_tready;
    assign s3_axis_tready  = sel_b ? m_axis_b_tready : 1'b0;

endmodule