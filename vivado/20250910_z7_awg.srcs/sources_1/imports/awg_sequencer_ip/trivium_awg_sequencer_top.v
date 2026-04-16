`timescale 1ns / 1ps

module trivium_awg_sequencer_top #(
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)(
    input wire clk,
    input wire resetn,
    input wire hw_trigger_in,

    // AXI-Lite Slave
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

    // AXI4 Master
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,
    output wire [7 : 0]                    m_axi_arlen,
    output wire [2 : 0]                    m_axi_arsize,
    output wire [1 : 0]                    m_axi_arburst,
    output wire                            m_axi_arvalid,
    input  wire                            m_axi_arready,
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,
    input  wire                            m_axi_rlast,
    input  wire                            m_axi_rvalid,
    output wire                            m_axi_rready,

    // AXI-Stream Master (Connects to External FIFO)
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    
    // Flush signal for External FIFO
    output wire        fifo_flush_n
);

    trivium_awg_sequencer #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) inst_sequencer (
        .clk(clk),
        .resetn(resetn),
        .hw_trigger_in(hw_trigger_in),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .fifo_flush_n(fifo_flush_n)
    );

endmodule
