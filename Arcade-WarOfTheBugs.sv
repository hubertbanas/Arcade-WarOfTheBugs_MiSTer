//============================================================================
//  Arcade: War Of The Bugs
//
//  Port to MiSTer
//  Copyright (C) 2018 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S    // 1 - signed audio samples, 0 - unsigned
);

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd1;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd1;

`include "build_id.v" 
localparam CONF_STR = {
	"A.WARBUG;;",
	"-;",
	"O1,Aspect Ratio,Original,Wide;",
	"O2,Orientation,Vert,Horz;",
	"O34,Scanlines(vert),No,25%,50%,75%;",
	"-;",
	"T6,Reset;",
	"J,Fire,Start 1P,Start 2P;",
	"V,v1.00.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_18, clk_6;
wire pll_locked;

wire clk_hdmi;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_18),
	.outclk_1(clk_sys),
	.outclk_2(clk_6),
	.outclk_3(clk_hdmi),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0,joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right

			'h029: btn_fire        <= pressed; // space
			'h014: btn_fire        <= pressed; // ctrl

			'h005: btn_one_player  <= pressed; // F1
			'h006: btn_two_players <= pressed; // F2
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_fire  = 0;
reg btn_one_player  = 0;
reg btn_two_players = 0;

wire m_up     = status[2] ? btn_left  | joy[1] : btn_up    | joy[3];
wire m_down   = status[2] ? btn_right | joy[0] : btn_down  | joy[2];
wire m_left   = status[2] ? btn_down  | joy[2] : btn_left  | joy[1];
wire m_right  = status[2] ? btn_up    | joy[3] : btn_right | joy[0];
wire m_fire   = btn_fire | joy[4];

wire m_start1 = btn_one_player  | joy[5];
wire m_start2 = btn_two_players | joy[6];
wire m_coin   = m_start1 | m_start2;

wire hblank, vblank;
wire ce_vid = clk_6;
wire hs, vs;
wire rde, rhs, rvs;
wire [2:0] r,g,rr,rg;
wire [2:0] b,rb;

assign VGA_CLK  = clk_sys;
assign VGA_CE   = ce_vid;
assign VGA_R    = {r,r,r[2:1]};
assign VGA_G    = {g,g,g[2:1]};
assign VGA_B    = {b,b,b[2:1]};
assign VGA_DE   = ~(hblank | vblank);
assign VGA_HS   = ~hs;
assign VGA_VS   = ~vs;

assign HDMI_CLK = status[2] ? VGA_CLK: clk_hdmi;
assign HDMI_CE  = status[2] ? VGA_CE : 1'b1;
assign HDMI_R   = status[2] ? VGA_R  : {rr,rr,rr[2:1]};
assign HDMI_G   = status[2] ? VGA_G  : {rg,rg,rg[2:1]};
assign HDMI_B   = status[2] ? VGA_B  : {rb,rb,rb[2:1]};
assign HDMI_DE  = status[2] ? VGA_DE : rde;
assign HDMI_HS  = status[2] ? VGA_HS : rhs;
assign HDMI_VS  = status[2] ? VGA_VS : rvs;
assign HDMI_SL  = status[2] ? 2'd0   : status[4:3];

screen_rotate #(257,224,9) screen_rotate
(
	.clk_in(clk_sys),
	.ce_in(ce_vid),
	.video_in({r,g,b}),
	.hblank(hblank),
	.vblank(vblank),

	.clk_out(clk_hdmi),
	.video_out({rr,rg,rb}),
	.hsync(rhs),
	.vsync(rvs),
	.de(rde)
);

wire [7:0] audio_a, audio_b;
wire [10:0] audio = {1'b0, audio_b, 2'b0} + {3'b0, audio_a};
assign AUDIO_L = {audio, 5'd0};
assign AUDIO_R = {audio, 5'd0};
assign AUDIO_S = 0;

galaxian warbug
(
	.W_CLK_18M(clk_18),
	.W_CLK_12M(clk_sys),
	.W_CLK_6M(clk_6),
	.I_RESET(RESET | status[0] | status[6] | buttons[1]),

	.P1_CSJUDLR({m_coin,m_start1,m_fire,m_up,m_down,m_left,m_right}),
	.P2_CSJUDLR({1'b0,  m_start2,m_fire,m_up,m_down,m_left,m_right}),

	.W_R(r),
	.W_G(g),
	.W_B(b),
	.W_H_SYNC(hs),
	.W_V_SYNC(vs),
	.HBLANK(hblank),
	.VBLANK(vblank),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr),

	.W_SDAT_A(audio_a),
	.W_SDAT_B(audio_b)
);

endmodule
