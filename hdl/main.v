// streams ram memory over uart
// designed for 115200 baud
module ram_to_uart #(
	parameter RAM_SIZE = PACKET_BUFFER_SIZE) (
	input clk, reset, start,
	// read_end points to one byte after the end, like in C
	input [clog2(RAM_SIZE)-1:0] read_start, read_end,
	input ram_read_ready,
	input [BYTE_LEN-1:0] ram_read_out,
	output uart_txd, reg ram_read_req = 0,
	output [clog2(RAM_SIZE)-1:0] ram_read_addr);

`include "params.vh"

localparam STATE_IDLE = 0;
localparam STATE_READING = 1;
localparam STATE_WRITING = 2;

reg [1:0] state = STATE_IDLE;

reg [clog2(RAM_SIZE)-1:0] curr_addr;
assign ram_read_addr = curr_addr;
reg [BYTE_LEN-1:0] data_buff;
reg data_ready = 0;
wire uart_tx_done;
uart_tx_driver uart_tx_driver_inst(
	.clk(clk), .reset(reset), .data_ready(data_ready),
	.data(data_buff), .txd(uart_txd), .done(uart_tx_done));

always @(posedge clk) begin
	if (reset) begin
		state <= STATE_IDLE;
		data_ready <= 0;
		ram_read_req <= 0;
	end else if (state == STATE_IDLE && start) begin
		curr_addr <= read_start;
		state <= STATE_READING;
		ram_read_req <= 1;
	end else if (state == STATE_READING && ram_read_ready) begin
		curr_addr <= curr_addr + 1;
		state <= STATE_WRITING;
		ram_read_req <= 0;
		data_ready <= 1;
		data_buff <= ram_read_out;
	end else if (state == STATE_WRITING && uart_tx_done) begin
		if (curr_addr == read_end)
			state <= STATE_IDLE;
		else begin
			state <= STATE_READING;
			ram_read_req <= 1;
		end
		data_ready <= 0;
	end
end

endmodule

// streams ram memory over ethernet
// TODO: upgrade this to include packet headers and crc
module packet_synth #(
	parameter RAM_SIZE = PACKET_SYNTH_ROM_SIZE) (
	input clk, reset,
	input start,
	// location of data in memory
	// data_ram_end_in, as usual, points to one byte after the last byte
	input [clog2(RAM_SIZE)-1:0] data_ram_start_in, data_ram_end_in,
	output eth_txen,
	output [1:0] eth_txd);

`include "params.vh"

reg [clog2(RAM_SIZE)-1:0] data_ram_end, ram_addr;
wire [clog2(RAM_SIZE)-1:0] next_ram_addr;
assign next_ram_addr = ram_addr + 1;

reg reading = 0;

wire clk_div4;
clock_divider #(.PULSE_PERIOD(4)) clk_div4_inst(
	.clk(clk), .start(start), .en(reading), .out(clk_div4));

wire ram_read_ready;
wire [BYTE_LEN-1:0] ram_read_out;
packet_synth_rom_driver packet_synth_rom_driver_inst(
	.clk(clk), .reset(reset),
	.read_req(clk_div4), .read_addr(ram_addr),
	.read_ready(ram_read_ready), .read_out(ram_read_out));
wire [1:0] btd_out;
bytes_to_dibits btd_inst(
	.clk(clk), .reset(reset), .inclk(ram_read_ready),
	.in(ram_read_out), .done_in(0),
	.out(btd_out), .outclk(eth_txen));
assign eth_txd = eth_txen ? btd_out : 2'b00;

always @(posedge clk) begin
	if (reset)
		reading <= 0;
	else if (start) begin
		ram_addr <= data_ram_start_in;
		data_ram_end <= data_ram_end_in;
		reading <= 1;
	end else if(clk_div4) begin
		if (next_ram_addr == data_ram_end)
			reading <= 0;
		ram_addr <= next_ram_addr;
	end
end

endmodule

// SW[0]: reset
// BTNC: dump ram
// BTNL: send sample packet
module main(
	input CLK100MHZ,
	input [15:0] SW,
	input BTNC, BTNU, BTNL, BTNR, BTND,
	output [7:0] JB,
	output [3:0] VGA_R,
	output [3:0] VGA_B,
	output [3:0] VGA_G,
	output VGA_HS,
	output VGA_VS,
	output LED16_B, LED16_G, LED16_R,
	output LED17_B, LED17_G, LED17_R,
	output [15:0] LED,
	output [7:0] SEG,  // segments A-G (0-6), DP (7)
	output [7:0] AN,	// Display 0-7
	inout ETH_CRSDV, ETH_RXERR,
	inout [1:0] ETH_RXD,
	output ETH_REFCLK, ETH_INTN, ETH_RSTN,
	input UART_TXD_IN, UART_RTS,
	output UART_RXD_OUT, UART_CTS,
	output ETH_TXEN,
	output [1:0] ETH_TXD,
	output ETH_MDC, ETH_MDIO,
	inout [15:0] ddr2_dq,
	inout [1:0] ddr2_dqs_n, ddr2_dqs_p,
	output [12:0] ddr2_addr,
	output [2:0] ddr2_ba,
	output ddr2_ras_n, ddr2_cas_n, ddr2_we_n,
	output [0:0] ddr2_ck_p, ddr2_ck_n, ddr2_cke, ddr2_cs_n,
	output [1:0] ddr2_dm,
	output [0:0] ddr2_odt
	);

`include "params.vh"

parameter RAM_SIZE = PACKET_BUFFER_SIZE;

wire clk_50mhz;

// the main clock for FPGA logic will be 50MHz
wire clk;
assign clk = clk_50mhz;

// 50MHz clock for Ethernet receiving
clk_wiz_0 clk_wiz_inst(
	.reset(0),
	.clk_in1(CLK100MHZ),
	.clk_out1(clk_50mhz));

wire reset;
delay #(.DELAY_LEN(SYNC_DELAY_LEN)) reset_delay(
	.clk(clk), .in(SW[0]), .out(reset));

wire [31:0] hex_display_data;
wire [6:0] segments;

display_8hex display(
	.clk(clk), .data(hex_display_data), .seg(segments), .strobe(AN));

assign SEG[7] = 1'b1;
assign SEG[6:0] = segments;

assign LED16_R = BTNL; // left button -> red led
assign LED16_G = BTNC; // center button -> green led
assign LED16_B = BTNR; // right button -> blue led
assign LED17_R = BTNL;
assign LED17_G = BTNC;
assign LED17_B = BTNR;

wire [10:0] hcount;
wire [9:0] vcount;
wire hsync, vsync, blank;

xvga xvga_inst(
	.vclock(clk), .hcount(hcount), .vcount(vcount),
	.hsync(hsync), .vsync(vsync), .blank(blank));

wire [3:0] vga_r, vga_g, vga_b;
assign {vga_r, vga_g, vga_b} = 0;
assign VGA_R = ~blank ? vga_r : 0;
assign VGA_G = ~blank ? vga_g : 0;
assign VGA_B = ~blank ? vga_b : 0;

assign VGA_HS = ~hsync;
assign VGA_VS = ~vsync;

assign UART_CTS = 1;

wire btnc_raw, btnl_raw, btnc, btnl;
sync_debounce sd_btnc(
	.reset(reset), .clk(clk), .in(BTNC), .out(btnc_raw));
sync_debounce sd_btnl(
	.reset(reset), .clk(clk), .in(BTNL), .out(btnl_raw));

pulse_generator pg_btnc(
	.clk(clk), .reset(reset), .in(btnc_raw), .out(btnc));
pulse_generator pg_btnl(
	.clk(clk), .reset(reset), .in(btnl_raw), .out(btnl));

wire ram_read_req, ram_read_ready, ram_write_enable;
wire [clog2(RAM_SIZE)-1:0] ram_read_addr, ram_write_addr;
wire [BYTE_LEN-1:0] ram_read_out, ram_write_val;
packet_buffer_ram_driver packet_buffer_ram_driver_inst(
	.clk(clk), .reset(reset),
	.read_req(ram_read_req), .read_addr(ram_read_addr),
	.read_ready(ram_read_ready), .read_out(ram_read_out),
	.write_enable(ram_write_enable),
	.write_addr(ram_write_addr), .write_val(ram_write_val));
ram_to_uart ram_to_uart_inst(
	.clk(clk), .reset(reset), .start(btnc),
	.read_start(0), .read_end(RAM_SIZE),
	.ram_read_ready(ram_read_ready), .ram_read_out(ram_read_out),
	.uart_txd(UART_RXD_OUT), .ram_read_req(ram_read_req),
	.ram_read_addr(ram_read_addr));

assign ETH_REFCLK = clk;
assign ETH_MDC = 0;
assign ETH_MDIO = 0;
wire eth_outclk, eth_done, eth_byte_outclk, eth_dtb_done;
wire [1:0] eth_out;
rmii_driver rmii_driv_inst(
	.clk(clk), .reset(reset),
	.crsdv_in(ETH_CRSDV), .rxd_in(ETH_RXD),
	.rxerr(ETH_RXERR),
	.intn(ETH_INTN), .rstn(ETH_RSTN),
	.out(eth_out),
	.outclk(eth_outclk), .done(eth_done));
dibits_to_bytes eth_dtb(
	.clk(clk), .reset(reset),
	.inclk(eth_outclk), .in(eth_out), .done_in(eth_done),
	.out(ram_write_val), .outclk(eth_byte_outclk), .done_out(eth_dtb_done));
assign ram_write_enable = eth_byte_outclk;

// maximum ethernet frame length is 1522 bytes
localparam MAX_ETH_FRAME_LEN = 1522;
reg [clog2(MAX_ETH_FRAME_LEN)-1:0] eth_byte_cnt = 0;
reg record = 1;
always @(posedge clk) begin
	if (reset) begin
		eth_byte_cnt <= 0;
		record <= 1;
	end else if (eth_done) begin
		eth_byte_cnt <= 0;
		record <= 0;
	end else if (eth_byte_outclk && record)
		eth_byte_cnt <= eth_byte_cnt + 1;
end
assign ram_write_addr = eth_byte_cnt;

wire eth_txen;
wire [1:0] eth_txd;
packet_synth packet_synth_inst(
	.clk(clk), .reset(reset), .start(btnl),
	.data_ram_start_in(0), .data_ram_end_in(73),
	.eth_txen(eth_txen), .eth_txd(eth_txd));

// buffer the outputs so that eth_txd calculation would be
// under timing constraints
delay eth_txen_delay(
	.clk(clk), .in(eth_txen), .out(ETH_TXEN));
delay #(.DATA_WIDTH(2)) eth_txd_delay(
	.clk(clk), .in(eth_txd), .out(ETH_TXD));

// DEBUGGING SIGNALS

wire blink;
blinker blinker_inst(
	.clk(clk), .reset(reset),
	.enable(1), .out(blink));

assign LED = {
	SW[15:2],
	blink,
	reset
};

assign hex_display_data = {
	4'h0, ram_write_addr, 4'h0, ram_read_addr
};

assign JB = {
	6'h0,
	UART_TXD_IN
};

endmodule
