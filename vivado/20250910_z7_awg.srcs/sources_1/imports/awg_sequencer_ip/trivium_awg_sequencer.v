`timescale 1ns / 1ps

module trivium_awg_sequencer #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 7,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer BURST_LEN = 16
)(
    input wire clk,
    input wire resetn,
    input wire hw_trigger_in,
    
    // --- AXI-Lite Slave Interface ---
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_awaddr,
    input  wire                            s_axi_awvalid,
    output wire                            s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_wdata,
    input  wire                            s_axi_wvalid,
    output wire                            s_axi_wready,
    output wire [1 : 0]                    s_axi_bresp,
    output wire                            s_axi_bvalid,
    input  wire                            s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0] s_axi_araddr,
    input  wire                            s_axi_arvalid,
    output wire                            s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] s_axi_rdata,
    output wire [1 : 0]                    s_axi_rresp,
    output wire                            s_axi_rvalid,
    input  wire                            s_axi_rready,

    // --- AXI-Full Master Interface ---
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,
    output wire [7 : 0]                    m_axi_arlen,
    output wire [2 : 0]                    m_axi_arsize,
    output wire [1 : 0]                    m_axi_arburst,
    output wire                            m_axi_arvalid,
    input  wire                            m_axi_arready,
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,
    input  wire [1 : 0]                    m_axi_rresp,
    input  wire                            m_axi_rlast,
    input  wire                            m_axi_rvalid,
    output wire                            m_axi_rready,

    // --- AXI-Stream Master Interface ---
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    
    output wire        fifo_flush_n
);

    // Software-facing registers
    reg [31:0] reg_ctrl;
    reg [31:0] reg_addr;
    reg [31:0] reg_len;
    reg        axi_err_flag;

    // Hardware-facing shadow registers (frozen during operation)
    reg [31:0] active_addr;
    reg [31:0] active_len;

    reg axi_awready, axi_wready, axi_bvalid, axi_arready, axi_rvalid;
    reg [31:0] axi_rdata;
    
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    localparam ST_IDLE = 2'd0, ST_REQ = 2'd1, ST_RECEIVE = 2'd2, ST_DISCARD = 2'd3;
    reg [1:0] state;

    // --- AXI-Lite Slave Logic ---
    always @(posedge clk) begin
        if (!resetn) begin
            axi_awready <= 0; axi_wready <= 0; axi_bvalid <= 0;
            axi_arready <= 0; axi_rvalid <= 0; axi_rdata <= 0;
            reg_ctrl <= 0; reg_addr <= 32'h30000000; reg_len <= 0;
        end else begin
            if (!axi_awready && s_axi_awvalid && s_axi_wvalid) axi_awready <= 1;
            else axi_awready <= 0;
            
            if (!axi_wready && s_axi_wvalid && s_axi_awvalid) axi_wready <= 1;
            else axi_wready <= 0;
            
            if (axi_awready && axi_wready) begin
                case (s_axi_awaddr[6:2])
                    5'h00: reg_ctrl <= s_axi_wdata;
                    // 5'h01 omitted: Status Register is Read-Only
                    5'h02: reg_addr <= s_axi_wdata; 
                    5'h03: reg_len  <= s_axi_wdata; 
                endcase
                axi_bvalid <= 1;
            end else if (s_axi_bready && axi_bvalid) axi_bvalid <= 0;

            if (!axi_arready && s_axi_arvalid) begin
                axi_arready <= 1;
                case (s_axi_araddr[6:2])
                    5'h00: axi_rdata <= reg_ctrl;               
                    5'h01: axi_rdata <= {29'd0, axi_err_flag, state}; 
                    5'h02: axi_rdata <= reg_addr;               
                    5'h03: axi_rdata <= reg_len;                
                    default: axi_rdata <= 32'hDEADBEEF;         
                endcase
            end else begin
                axi_arready <= 0;
            end

            if (axi_arready && s_axi_arvalid && !axi_rvalid) axi_rvalid <= 1;
            else if (axi_rvalid && s_axi_rready) axi_rvalid <= 0;
        end
    end

    // --- Clock Domain Crossing & Trigger Synchronization ---
    reg trig_m1, trig_sync;
    reg hw_abort_latched;
    reg fifo_flush_reg;

    always @(posedge clk) begin
        if (!resetn) begin
            trig_m1 <= 0;
            trig_sync <= 0;
        end else begin
            trig_m1 <= hw_trigger_in;
            trig_sync <= trig_m1;
        end
    end

    always @(posedge clk) begin
        if (!resetn || (state == ST_IDLE && !reg_ctrl[0])) begin
            hw_abort_latched <= 0;
            fifo_flush_reg <= 1;
        end else if (reg_ctrl[3] && trig_sync) begin
            hw_abort_latched <= 1;
            fifo_flush_reg <= 0; 
        end
    end
    
    assign fifo_flush_n = fifo_flush_reg;

    // --- AXI Master & AXI-Stream Engine ---
    reg [31:0] word_cnt;
    reg [7:0]  timeout_cnt; 
    reg [7:0]  burst_len_issued; // Pipeline register to break combinational loop
    
    // Dynamic Burst Length uses the frozen shadow register (active_len)
    wire [31:0] words_remaining = active_len - word_cnt;
    assign m_axi_arlen   = (words_remaining < BURST_LEN) ? (words_remaining - 1) : (BURST_LEN - 1);
    
    // Address generation uses the frozen shadow register (active_addr)
    assign m_axi_araddr  = active_addr + (word_cnt << 2);
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == ST_REQ);
    
    assign m_axi_rready  = (state == ST_RECEIVE) ? m_axis_tready : (state == ST_DISCARD);
    assign m_axis_tvalid = (state == ST_RECEIVE) && m_axi_rvalid;
    assign m_axis_tdata  = m_axi_rdata;

    // --- Core FSM ---
    always @(posedge clk) begin
        if (!resetn) begin
            state <= ST_IDLE;
            word_cnt <= 0;
            timeout_cnt <= 0;
            axi_err_flag <= 0;
            active_addr <= 0;
            active_len <= 0;
            burst_len_issued <= 0;
        end else begin
            if (state == ST_IDLE && !reg_ctrl[0]) begin
                axi_err_flag <= 0;
            end else if (m_axi_rvalid && m_axi_rready && m_axi_rresp[1]) begin
                axi_err_flag <= 1;
            end

            case (state)
                ST_IDLE: begin
                    if (reg_ctrl[0] && reg_len > 0) begin
                        state <= ST_REQ;
                        // Shadow the registers at the exact moment of launch
                        active_addr <= reg_addr;
                        active_len  <= reg_len;
                    end
                    word_cnt <= 0;
                    timeout_cnt <= 0;
                end
                
                ST_REQ: begin
                    timeout_cnt <= timeout_cnt + 1;
                    if (m_axi_arready) begin
                        // Latch the exact burst length issued to the interconnect
                        burst_len_issued <= m_axi_arlen;
                        
                        if (!reg_ctrl[0] || hw_abort_latched) begin
                            state <= ST_DISCARD; 
                        end else begin
                            state <= ST_RECEIVE; 
                        end
                    end else if (timeout_cnt == 8'hFF) begin
                        state <= ST_IDLE; 
                        timeout_cnt <= 0; 
                    end
                end
                
                ST_RECEIVE: begin
                    if (m_axi_rvalid && m_axis_tready) begin
                        if (m_axi_rlast) begin
                            if (!reg_ctrl[0] || hw_abort_latched) begin
                                state <= ST_IDLE;
                            end else begin
                                // Utilize the registered burst length, breaking the timing path
                                if (word_cnt + (burst_len_issued + 1) >= active_len) begin
                                    state <= ST_REQ;
                                    word_cnt <= 0;
                                    timeout_cnt <= 0;
                                end else begin
                                    state <= ST_REQ;
                                    word_cnt <= word_cnt + (burst_len_issued + 1);
                                    timeout_cnt <= 0;
                                end
                            end
                        end else begin
                            if (!reg_ctrl[0] || hw_abort_latched) begin
                                state <= ST_DISCARD; 
                            end
                        end
                    end else begin
                        if (!reg_ctrl[0] || hw_abort_latched) begin
                            state <= ST_DISCARD; 
                        end
                    end
                end
                
                ST_DISCARD: begin
                    if (m_axi_rvalid && m_axi_rlast) state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule