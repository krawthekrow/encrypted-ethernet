`timescale 1ns / 1ps

module test_ethernet_driver();

`include "params.vh"

reg clk = 0;
// 50MHz clock
initial forever #10 clk = ~clk;

reg reset = 1;
wire crsdv_tr = 1'bz, rxerr_tr = 1'bz;
wire [1:0] rxd_tr = 2'bzz;
reg crsdv, rxerr;
reg [1:0] rxd;
reg reset_done = 0;
assign crsdv_tr = reset_done ? crsdv : 1'bz;
assign rxerr_tr = reset_done ? rxerr : 1'bz;
assign rxd_tr = reset_done ? rxd : 2'bzz;
wire intn, rstn;
wire [1:0] eth_out;
wire eth_outclk, eth_done;
wire [BYTE_LEN-1:0] eth_byte_out;
wire eth_byte_outclk, eth_dtb_done;
rmii_driver rmii_driv_inst(
	.clk(clk), .reset(reset),
	.crsdv_in(crsdv_tr), .rxd_in(rxd_tr),
	.rxerr(rxerr_tr),
	.intn(intn), .rstn(rstn),
	.out(eth_out),
	.outclk(eth_outclk), .done(eth_done));
dibits_to_bytes eth_dtb(
	.clk(clk), .reset(reset),
	.inclk(eth_outclk), .in(eth_out), .done_in(eth_done),
	.out(eth_byte_out), .outclk(eth_byte_outclk), .done_out(eth_dtb_done));

initial begin
	#100
	reset = 0;
	// reset sequence
	#400
	reset_done = 1;
	rxerr = 0;
	rxd = 0;
	crsdv = 0;
	#100
	crsdv = 1;
	#100

	// 28 cycles = 56 bits
	rxd = 2'b01;
	#540
	rxd = 2'b11;
	#20

	// send 10101010 twice (2 bytes)
	rxd = 2'b10;
	#160

	rxd = 0;
	crsdv = 0;
	#160

	$stop();
end

endmodule

module test_ddr2_ram();

`include "params.vh"

reg clk_100mhz = 0;
// 100MHz clock
initial forever #5 clk_100mhz = ~clk_100mhz;

// clk will be 50MHz
wire clk, clk_200mhz;
clk_wiz_0 clk_wiz_inst(
	.reset(0),
	.clk_in1(clk_100mhz), .clk_out1(clk), .clk_out2(clk_200mhz));

wire [15:0] ddr2_dq;
wire [1:0] ddr2_dqs_n, ddr2_dqs_p;
wire [12:0] ddr2_addr;
wire [2:0] ddr2_ba;
wire ddr2_ras_n, ddr2_cas_n, ddr2_we_n;
wire [0:0] ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n;
wire [1:0] ddr2_dm;
wire [0:0] ddr2_odt;
reg [26:0] app_addr = 0;
reg [2:0] app_cmd = 3'b111;
reg app_en = 0;
reg [63:0] app_wdf_data = 0;
reg app_wdf_end = 0;
reg [7:0] app_wdf_mask = 0;
reg app_wdf_wren = 0;
wire [63:0] app_rd_data;
wire app_rd_data_end, app_rd_data_valid, app_rdy, app_wdf_rdy;
wire ui_clk, ui_clk_sync_rst, init_calib_complete;
reg sys_rst = 0;
`define x16
`define sg25
ddr2_mcp ddr2_mcp_inst(
	.ck(ddr2_ck_p), .ck_n(ddr2_ck_n), .cke(ddr2_cke),
	.cs_n(ddr2_cs_n),
	.ras_n(ddr2_ras_n), .cas_n(ddr2_cas_n), .we_n(ddr2_we_n),
	.dm_rdqs(ddr2_dm), .ba(ddr2_ba), .addr(ddr2_addr),
	.dq(ddr2_dq), .dqs(ddr2_dqs_p), .dqs_n(ddr2_dqs_n),
	.odt(ddr2_odt));
nexys4_ddr2 ddr2_ram_inst(
	.ddr2_dq(ddr2_dq), .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p),
	.ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba),
	.ddr2_ras_n(ddr2_ras_n), .ddr2_cas_n(ddr2_cas_n), .ddr2_we_n(ddr2_we_n),
	.ddr2_ck_p(ddr2_ck_p), .ddr2_ck_n(ddr2_ck_n), .ddr2_cke(ddr2_cke),
	.ddr2_cs_n(ddr2_cs_n),
	.ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt), .sys_clk_i(clk_200mhz),
	.sys_rst(sys_rst), .app_sr_req(0), .app_ref_req(0), .app_zq_req(0),
	.app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en),
	.app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end),
	.app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
	.app_rd_data(app_rd_data), .app_rd_data_end(app_rd_data_end),
	.app_rd_data_valid(app_rd_data_valid),
	.app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy),
	.ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst),
	.init_calib_complete(init_calib_complete));

initial begin
	#400
	sys_rst = 1;
	#1000000
	$stop();
end

endmodule

module test_crc();

`include "params.vh"

localparam RAM_SIZE = PACKET_SYNTH_ROM_SIZE;

reg clk = 0;
// 50MHz clock
initial forever #10 clk = ~clk;

reg reset = 1;
wire read_req;
reg [clog2(RAM_SIZE)-1:0] read_addr = 0;
wire read_ready;
wire [BYTE_LEN-1:0] read_out;
packet_synth_rom_driver packet_synth_rom_driver_inst(
	.clk(clk), .reset(reset), .read_req(read_req), .read_addr(read_addr),
	.read_ready(read_ready), .read_out(read_out));
reg done_in = 0;
wire [1:0] dibit_out;
wire byte_clk, done_out;
wire btd_idle;
bytes_to_dibits btd_inst(
	.clk(clk), .reset(reset), .inclk(read_ready),
	.in(read_out), .done_in(done_in),
	.out(dibit_out), .outclk(byte_clk), .idle(btd_idle),
	.done_out(done_out));
wire [31:0] crc;
crc32 crc32_inst(
	.clk(clk), .reset(reset), .inclk(byte_clk),
	.in(dibit_out), .out(crc));

reg reading = 0;
reg [clog2(BYTE_LEN)-2:0] dibit_cnt;
always @(posedge clk) begin
	if (reset)
		dibit_cnt = 0;
	else if (reading) begin
		if (dibit_cnt == BYTE_LEN/2-1)
			read_addr <= read_addr + 1;
		dibit_cnt <= dibit_cnt + 1;
	end
end
assign read_req = reading && dibit_cnt == 0;

initial begin
	#100
	reset = 0;

	// reset sequence
	#400

	reading = 1;
	// read out sample packet
	// 62 bytes * 4 dibits * 20ns
	#4960
	reading = 0;

	#100

	$stop();
end

endmodule

module test_packet_synth();

reg clk_100mhz = 0;
// 100MHz clock
initial forever #5 clk_100mhz = ~clk_100mhz;

wire clk;
clk_wiz_0 clk_wiz_inst(
	.reset(0),
	.clk_in1(clk_100mhz),
	.clk_out1(clk));

reg reset = 1, start = 0;
wire eth_txen;
wire [1:0] eth_txd;
packet_synth packet_synth_inst(
	.clk(clk), .reset(reset), .start(start),
	.data_ram_start_in(0), .data_ram_end_in(73),
	.eth_txen(eth_txen), .eth_txd(eth_txd));

initial begin
	#2000
	reset = 0;

	// reset sequence
	#400

	start = 1;
	#20
	start = 0;

	// bytes * dibits/byte * ns/dibit
	#(73 * 4 * 20)

	#100

	$stop();
end

endmodule



module test_aes_one_block_encrypt();

reg clk_100mhz = 0;
// 100MHz clock
initial forever #5 clk_100mhz = ~clk_100mhz;

wire clk;
clk_wiz_0 clk_wiz_inst(
	.reset(0),
	.clk_in1(clk_100mhz),
	.clk_out1(clk));

reg [127:0] in;
reg [127:0] key;
wire [127:0] out;

aes_encrypt_block aes(
	.in(in), .key(key), .out(out));

initial begin
	#100
	in = 200;
    key = 0;
	#1000

	$stop();
end

endmodule

module test_fast_uart();

`include "params.vh"

reg clk_100mhz = 0;
// 100MHz clock
initial forever #5 clk_100mhz = ~clk_100mhz;

reg clk_12mbaud = 0;
initial forever #41.6667 clk_12mbaud = ~clk_12mbaud;

wire clk, clk_120mhz;
clk_wiz_0 clk_wiz_inst(
	.reset(1'b0),
	.clk_in1(clk_100mhz),
	.clk_out1(clk),
	.clk_out3(clk_120mhz));

reg reset = 1;

localparam RAM_SIZE = PACKET_BUFFER_SIZE;

wire ram_readclk, ram_we, ram_outclk;
wire [clog2(RAM_SIZE)-1:0] ram_raddr, ram_waddr;
wire [BYTE_LEN-1:0] ram_win, ram_out;
packet_buffer_ram_driver ram_driv_inst(
	.clk(clk), .rst(reset),
	.readclk(ram_readclk), .raddr(ram_raddr),
	.we(ram_we), .waddr(ram_waddr), .win(ram_win),
	.outclk(ram_outclk), .out(ram_out));

wire uart_rxd;
wire [7:0] uart_out;
wire uart_outclk;
uart_rx_fast_driver uart_rx_inst (
	.clk(clk), .clk_120mhz(clk_120mhz), .reset(reset),
	.rxd(uart_rxd), .out(uart_out), .outclk(uart_outclk));
stream_to_memory uart_stm_inst(
	.clk(clk), .rst(reset),
	.set_offset_req(1'b0), .set_offset_val(0),
	.inclk(uart_outclk), .in(uart_out),
	.ram_we(ram_we), .ram_waddr(ram_waddr),
	.ram_win(ram_win));

reg sfm_start = 0;

wire uart_inclk;
wire [BYTE_LEN-1:0] uart_in;
wire uart_txd, uart_tx_ready;
uart_tx_fast_stream_driver uart_tx_inst(
	.clk(clk), .clk_120mhz(clk_120mhz), .reset(reset), .start(sfm_start),
	.inclk(uart_inclk), .in(uart_in), .txd(uart_txd),
	.ready(uart_tx_ready));
stream_from_memory uart_sfm_inst(
	.clk(clk), .rst(reset), .start(sfm_start),
	.read_start(0), .read_end(3),
	.downstream_rdy(uart_tx_ready),
	.ram_outclk(ram_outclk), .ram_out(ram_out),
	.ram_readclk(ram_readclk), .ram_raddr(ram_raddr),
	.outclk(uart_inclk), .out(uart_in));

reg [31:0] test_data = 32'b10_10011011_10_11010000_110_10001111_1;
assign uart_rxd = test_data[31];
reg sending = 0;
always @(posedge clk_12mbaud) begin
	if (sending)
		test_data <= {test_data[30:0], test_data[31]};
end

initial begin
	#2000
	reset = 0;
	#20
	sending = 1;
	#(32 * 2 * 41.6667)
	#40
	sfm_start = 1;
	#20
	sfm_start = 0;
	#(32 * 2 * 41.6667)
	#40
	$stop();
end

endmodule

module test_main();

reg clk_100mhz = 0;
// 100MHz clock
initial forever #5 clk_100mhz = ~clk_100mhz;

wire clk, clk_120mhz;
clk_wiz_0 clk_wiz_inst(
	.reset(0),
	.clk_in1(clk_100mhz),
	.clk_out1(clk),
	.clk_out3(clk_120mhz));

initial begin
	#10000
	$stop();
end

endmodule

module test_bytes_to_colors();

`include "params.vh"

reg clk = 0;
// 50MHz clock
initial forever #10 clk = ~clk;

reg reset = 1;
reg btc_inclk = 0;
wire [BYTE_LEN-1:0] btc_in;
wire btc_outclk;
wire [COLOR_LEN-1:0] btc_out;

bytes_to_colors btc_inst(
	.clk(clk), .reset(reset), .inclk(btc_inclk), .in(btc_in),
	.outclk(btc_outclk), .out(btc_out));
reg [4*COLOR_LEN-1:0] in_data_shifted = 48'hDEADBEEFCAFE;
assign btc_in = in_data_shifted[0+:BYTE_LEN];

wire vram_readclk, vram_outclk, vram_we;
wire [clog2(VIDEO_CACHE_RAM_SIZE)-1:0] vram_raddr, vram_waddr;
wire [COLOR_LEN-1:0] vram_read_out, vram_write_val;
video_cache_ram_driver vram_driv_inst(
	.clk(clk), .rst(reset),
	.readclk(vram_readclk), .raddr(vram_raddr),
	.we(vram_we), .waddr(vram_waddr), .win(vram_win),
	.outclk(vram_outclk), .read_out(vram_out));
stream_to_memory
	#(.RAM_SIZE(VIDEO_CACHE_RAM_SIZE), .WORD_LEN(COLOR_LEN)) stm_inst(
	.clk(clk), .rst(reset), .set_offset_req(0), .set_offset_val(0),
	.inclk(btc_outclk), .in(btc_out),
	.ram_we(vram_we), .ram_waddr(vram_waddr),
	.ram_win(vram_win));
assign vram_readclk = 0;
assign vram_raddr = 0;

always @(posedge clk) begin
	if (btc_inclk)
		in_data_shifted <= {in_data_shifted[0+:BYTE_LEN],
			in_data_shifted[BYTE_LEN+:BYTE_LEN]};
end

initial begin
	#100
	reset = 0;
	#100
	btc_inclk = 1;
	#(6 * 20)
	#100
	$stop();
end

endmodule
