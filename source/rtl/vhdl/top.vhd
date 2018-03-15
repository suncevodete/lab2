-------------------------------------------------------------------------------
--  Department of Computer Engineering and Communications
--  Author: LPRS2  <lprs2@rt-rk.com>
--
--  Module Name: top
--
--  Description:
--
--    Simple test for VGA control
--
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity top is
  generic (
    RES_TYPE             : natural := 1;
    TEXT_MEM_DATA_WIDTH  : natural := 6;
    GRAPH_MEM_DATA_WIDTH : natural := 32
    );
  port (
    clk_i          : in  std_logic;
    reset_n_i      : in  std_logic;
    -- vga
    vga_hsync_o    : out std_logic;
    vga_vsync_o    : out std_logic;
    blank_o        : out std_logic;
    pix_clock_o    : out std_logic;
    psave_o        : out std_logic;
    sync_o         : out std_logic;
    red_o          : out std_logic_vector(7 downto 0);
    green_o        : out std_logic_vector(7 downto 0);
    blue_o         : out std_logic_vector(7 downto 0)
   );
end top;

architecture rtl of top is

  constant RES_NUM : natural := 6;

  type t_param_array is array (0 to RES_NUM-1) of natural;
  
  constant H_RES_ARRAY           : t_param_array := ( 0 => 64, 1 => 640,  2 => 800,  3 => 1024,  4 => 1152,  5 => 1280,  others => 0 );
  constant V_RES_ARRAY           : t_param_array := ( 0 => 48, 1 => 480,  2 => 600,  3 => 768,   4 => 864,   5 => 1024,  others => 0 );
  constant MEM_ADDR_WIDTH_ARRAY  : t_param_array := ( 0 => 12, 1 => 14,   2 => 13,   3 => 14,    4 => 14,    5 => 15,    others => 0 );
  constant MEM_SIZE_ARRAY        : t_param_array := ( 0 => 48, 1 => 4800, 2 => 7500, 3 => 12576, 4 => 15552, 5 => 20480, others => 0 ); 
  
  constant H_RES          : natural := H_RES_ARRAY(RES_TYPE);
  constant V_RES          : natural := V_RES_ARRAY(RES_TYPE);
  constant MEM_ADDR_WIDTH : natural := MEM_ADDR_WIDTH_ARRAY(RES_TYPE);
  constant MEM_SIZE       : natural := MEM_SIZE_ARRAY(RES_TYPE);

  component vga_top is 
    generic (
      H_RES                : natural := 640;
      V_RES                : natural := 480;
      MEM_ADDR_WIDTH       : natural := 32;
      GRAPH_MEM_ADDR_WIDTH : natural := 32;
      TEXT_MEM_DATA_WIDTH  : natural := 32;
      GRAPH_MEM_DATA_WIDTH : natural := 32;
      RES_TYPE             : integer := 1;
      MEM_SIZE             : natural := 4800
      );
    port (
      clk_i               : in  std_logic;
      reset_n_i           : in  std_logic;
      --
      direct_mode_i       : in  std_logic; -- 0 - text and graphics interface mode, 1 - direct mode (direct force RGB component)
      dir_red_i           : in  std_logic_vector(7 downto 0);
      dir_green_i         : in  std_logic_vector(7 downto 0);
      dir_blue_i          : in  std_logic_vector(7 downto 0);
      dir_pixel_column_o  : out std_logic_vector(10 downto 0);
      dir_pixel_row_o     : out std_logic_vector(10 downto 0);
      -- mode interface
      display_mode_i      : in  std_logic_vector(1 downto 0);  -- 00 - text mode, 01 - graphics mode, 01 - text & graphics
      -- text mode interface
      text_addr_i         : in  std_logic_vector(MEM_ADDR_WIDTH-1 downto 0);
      text_data_i         : in  std_logic_vector(TEXT_MEM_DATA_WIDTH-1 downto 0);
      text_we_i           : in  std_logic;
      -- graphics mode interface
      graph_addr_i        : in  std_logic_vector(GRAPH_MEM_ADDR_WIDTH-1 downto 0);
      graph_data_i        : in  std_logic_vector(GRAPH_MEM_DATA_WIDTH-1 downto 0);
      graph_we_i          : in  std_logic;
      --
      font_size_i         : in  std_logic_vector(3 downto 0);
      show_frame_i        : in  std_logic;
      foreground_color_i  : in  std_logic_vector(23 downto 0);
      background_color_i  : in  std_logic_vector(23 downto 0);
      frame_color_i       : in  std_logic_vector(23 downto 0);
      -- vga
      vga_hsync_o         : out std_logic;
      vga_vsync_o         : out std_logic;
      blank_o             : out std_logic;
      pix_clock_o         : out std_logic;
      vga_rst_n_o         : out std_logic;
      psave_o             : out std_logic;
      sync_o              : out std_logic;
      red_o               : out std_logic_vector(7 downto 0);
      green_o             : out std_logic_vector(7 downto 0);
      blue_o              : out std_logic_vector(7 downto 0)
    );
  end component;
  
  component ODDR2
  generic(
   DDR_ALIGNMENT : string := "NONE";
   INIT          : bit    := '0';
   SRTYPE        : string := "SYNC"
   );
  port(
    Q           : out std_ulogic;
    C0          : in  std_ulogic;
    C1          : in  std_ulogic;
    CE          : in  std_ulogic := 'H';
    D0          : in  std_ulogic;
    D1          : in  std_ulogic;
    R           : in  std_ulogic := 'L';
    S           : in  std_ulogic := 'L'
  );
  end component;
  
  
  constant update_period     : std_logic_vector(31 downto 0) := conv_std_logic_vector(1, 32);
  
  constant GRAPH_MEM_ADDR_WIDTH : natural := MEM_ADDR_WIDTH + 6;-- graphics addres is scales with minumum char size 8*8 log2(64) = 6
  
  -- text
  signal message_lenght      : std_logic_vector(MEM_ADDR_WIDTH-1 downto 0);
  signal graphics_lenght     : std_logic_vector(GRAPH_MEM_ADDR_WIDTH-1 downto 0);
  
  signal direct_mode         : std_logic;
  --
  signal font_size           : std_logic_vector(3 downto 0);
  signal show_frame          : std_logic;
  signal display_mode        : std_logic_vector(1 downto 0);  -- 01 - text mode, 10 - graphics mode, 11 - text & graphics
  signal foreground_color    : std_logic_vector(23 downto 0);
  signal background_color    : std_logic_vector(23 downto 0);
  signal frame_color         : std_logic_vector(23 downto 0);

  signal char_we             : std_logic;
  signal char_address        : std_logic_vector(MEM_ADDR_WIDTH-1 downto 0);
  signal char_value          : std_logic_vector(5 downto 0);

  signal pixel_address       : std_logic_vector(GRAPH_MEM_ADDR_WIDTH-1 downto 0);
  signal pixel_value         : std_logic_vector(GRAPH_MEM_DATA_WIDTH-1 downto 0);
  signal pixel_we            : std_logic;

  signal pix_clock_s         : std_logic;
  signal vga_rst_n_s         : std_logic;
  signal pix_clock_n         : std_logic;
   
  signal dir_red             : std_logic_vector(7 downto 0);
  signal dir_green           : std_logic_vector(7 downto 0);
  signal dir_blue            : std_logic_vector(7 downto 0);
  signal dir_pixel_column    : std_logic_vector(10 downto 0);
  signal dir_pixel_row       : std_logic_vector(10 downto 0);
  
  
  --added signals
  signal char_address_next : std_logic_vector(MEM_ADDR_WIDTH-1 downto 0); --signal for register
  signal base : std_logic_vector(13 downto 0); --1 sec enable for graph mem
  signal cnt : std_logic_vector(23 downto 0); --1 sec enable for graph mem
	signal base1 : std_logic_vector(13 downto 0); --1 sec enable for txt mem
  signal cnt1 : std_logic_vector(23 downto 0); --1 sec enable for txt mem
begin

  -- calculate message lenght from font size
  message_lenght <= conv_std_logic_vector(MEM_SIZE/64, MEM_ADDR_WIDTH)when (font_size = 3) else -- note: some resolution with font size (32, 64)  give non integer message lenght (like 480x640 on 64 pixel font size) 480/64= 7.5
                    conv_std_logic_vector(MEM_SIZE/16, MEM_ADDR_WIDTH)when (font_size = 2) else
                    conv_std_logic_vector(MEM_SIZE/4 , MEM_ADDR_WIDTH)when (font_size = 1) else
                    conv_std_logic_vector(MEM_SIZE   , MEM_ADDR_WIDTH);
  
  graphics_lenght <= conv_std_logic_vector(MEM_SIZE*8*8, GRAPH_MEM_ADDR_WIDTH);
  
  -- removed to inputs pin
  direct_mode <= '0';
  display_mode     <= "01";  -- 01 - text mode, 10 - graphics mode, 11 - text & graphics
  
  font_size        <= x"1";
  show_frame       <= '0';
  foreground_color <= x"FFFFFF";
  background_color <= x"000000";
  frame_color      <= x"FF0000";

  clk5m_inst : ODDR2
  generic map(
    DDR_ALIGNMENT => "NONE",  -- Sets output alignment to "NONE","C0", "C1" 
    INIT => '0',              -- Sets initial state of the Q output to '0' or '1'
    SRTYPE => "SYNC"          -- Specifies "SYNC" or "ASYNC" set/reset
  )
  port map (
    Q  => pix_clock_o,       -- 1-bit output data
    C0 => pix_clock_s,       -- 1-bit clock input
    C1 => pix_clock_n,       -- 1-bit clock input
    CE => '1',               -- 1-bit clock enable input
    D0 => '1',               -- 1-bit data input (associated with C0)
    D1 => '0',               -- 1-bit data input (associated with C1)
    R  => '0',               -- 1-bit reset input
    S  => '0'                -- 1-bit set input
  );
  pix_clock_n <= not(pix_clock_s);

  -- component instantiation
  vga_top_i: vga_top
  generic map(
    RES_TYPE             => RES_TYPE,
    H_RES                => H_RES,
    V_RES                => V_RES,
    MEM_ADDR_WIDTH       => MEM_ADDR_WIDTH,
    GRAPH_MEM_ADDR_WIDTH => GRAPH_MEM_ADDR_WIDTH,
    TEXT_MEM_DATA_WIDTH  => TEXT_MEM_DATA_WIDTH,
    GRAPH_MEM_DATA_WIDTH => GRAPH_MEM_DATA_WIDTH,
    MEM_SIZE             => MEM_SIZE
  )
  port map(
    clk_i              => clk_i,
    reset_n_i          => reset_n_i,
    --
    direct_mode_i      => direct_mode,
    dir_red_i          => dir_red,
    dir_green_i        => dir_green,
    dir_blue_i         => dir_blue,
    dir_pixel_column_o => dir_pixel_column,
    dir_pixel_row_o    => dir_pixel_row,
    -- cfg
    display_mode_i     => display_mode,  -- 01 - text mode, 10 - graphics mode, 11 - text & graphics
    -- text mode interface
    text_addr_i        => char_address,
    text_data_i        => char_value,
    text_we_i          => char_we,
    -- graphics mode interface
    graph_addr_i       => pixel_address,
    graph_data_i       => pixel_value,
    graph_we_i         => pixel_we,
    -- cfg
    font_size_i        => font_size,
    show_frame_i       => show_frame,
    foreground_color_i => foreground_color,
    background_color_i => background_color,
    frame_color_i      => frame_color,
    -- vga
    vga_hsync_o        => vga_hsync_o,
    vga_vsync_o        => vga_vsync_o,
    blank_o            => blank_o,
    pix_clock_o        => pix_clock_s,
    vga_rst_n_o        => vga_rst_n_s,
    psave_o            => psave_o,
    sync_o             => sync_o,
    red_o              => red_o,
    green_o            => green_o,
    blue_o             => blue_o     
  );
  
  -- na osnovu signala iz vga_top modula dir_pixel_column i dir_pixel_row realizovati logiku koja genereise
  --dir_red
  --dir_green
  --dir_blue
	dir_red <= x"00" when dir_pixel_column >= 0 and dir_pixel_column <= 319 else
				  x"ff";
				  
	dir_green <= x"00" when dir_pixel_column >= 0 and dir_pixel_column <= 159 else
					 x"00" when dir_pixel_column >= 320 and dir_pixel_column <= 479 else
					 x"ff";
					 
	dir_blue <= x"00" when dir_pixel_column >= 0 and dir_pixel_column <= 79 else
					x"00" when dir_pixel_column >= 160 and dir_pixel_column <= 239 else
					x"00" when dir_pixel_column >= 320 and dir_pixel_column <= 399 else
					x"00" when dir_pixel_column >= 480 and dir_pixel_column <= 559 else
					x"ff";
 
  -- koristeci signale realizovati logiku koja pise po TXT_MEM
  --char_address
  --char_value
  --char_we
  char_we <= '1';

	--register
	process(pix_clock_s, reset_n_i)
	begin
		if reset_n_i = '0' then
			char_address <= (others => '0');
			base1 <= (others => '0');
			cnt1 <= (others => '0');
		elsif rising_edge(pix_clock_s) then
			if cnt1 < 2000000 then
				cnt1 <= cnt1+1;
				base1 <= base1;
			else
				base1 <= base1 + 1;
				cnt1 <= (others=>'0');
			end if;
			if char_address < 4800 then
				char_address <= char_address + 1;
			else
				char_address <= base1; --<=base
			end if;
		end if;
	end process;
	
	char_value <= "001010" when char_address = 1+base1 else --J
					  "000101" when char_address = 2+base1 else --E
					  "001100" when char_address = 3+base1 else --L
					  "000101" when char_address = 4+base1 else --E
					  "001110" when char_address = 5+base1 else --N
					  "000001" when char_address = 6+base1 else --A
					  "100000" when char_address = 7+base1 else --space
					  "000010" when char_address = 8+base1 else --B
					  "001111" when char_address = 9+base1 else --O
					  "010010" when char_address = 10+base1 else --R
					  "001111" when char_address = 11+base1 else --O
					  "001010" when char_address = 12+base1 else --J
					  "000001" when char_address = 13+base1 else --A +base 
					  "100000"; --space
	
	
  
  -- koristeci signale realizovati logiku koja pise po GRAPH_MEM
  --pixel_address
  --pixel_value
  --pixel_we
  
  pixel_we <= '1';
  
  process(pix_clock_s, reset_n_i)
	begin
		if reset_n_i = '0' then
			pixel_address <= (others => '0');
			cnt <= (others=>'0');
			base <= (others=>'0');
		elsif rising_edge(pix_clock_s) then
			if cnt = 2000000 then
				if base < 20 then
					base <= base +1;
				else
				   base <= (others => '0');
				end if;
				
				cnt <= (others=>'0');
			else
				cnt <= cnt+1;
			end if;
				
				
			if pixel_address < 9600 then
				pixel_address <= pixel_address + 1;
			else
				pixel_address <= (others => '0');
			end if;
		end if;
	end process;
  

	pixel_value <= 
						(others=>'1') when pixel_address >= 208*20+base and pixel_address <= 208*20+base+1 else
						(others=>'1') when pixel_address >= 209*20+base and pixel_address <= 209*20+base+1 else
						(others=>'1') when pixel_address >= 210*20+base and pixel_address <= 210*20+base+1 else
						(others=>'1') when pixel_address >= 211*20+base and pixel_address <= 211*20+base+1 else
						(others=>'1') when pixel_address >= 212*20+base and pixel_address <= 212*20+base+1 else
						(others=>'1') when pixel_address >= 213*20+base and pixel_address <= 213*20+base+1 else
						(others=>'1') when pixel_address >= 214*20+base and pixel_address <= 214*20+base+1 else
						(others=>'1') when pixel_address >= 215*20+base and pixel_address <= 215*20+base+1 else
						(others=>'1') when pixel_address >= 216*20+base and pixel_address <= 216*20+base+1 else
						(others=>'1') when pixel_address >= 217*20+base and pixel_address <= 217*20+base+1 else
						(others=>'1') when pixel_address >= 218*20+base and pixel_address <= 218*20+base+1 else
						(others=>'1') when pixel_address >= 219*20+base and pixel_address <= 219*20+base+1 else
						(others=>'1') when pixel_address >= 220*20+base and pixel_address <= 220*20+base+1 else
						(others=>'1') when pixel_address >= 221*20+base and pixel_address <= 221*20+base+1 else
						(others=>'1') when pixel_address >= 222*20+base and pixel_address <= 222*20+base+1 else
						(others=>'1') when pixel_address >= 223*20+base and pixel_address <= 223*20+base+1 else
						(others=>'1') when pixel_address >= 224*20+base and pixel_address <= 224*20+base+1 else
						(others=>'1') when pixel_address >= 225*20+base and pixel_address <= 225*20+base+1 else
						(others=>'1') when pixel_address >= 226*20+base and pixel_address <= 226*20+base+1 else
						(others=>'1') when pixel_address >= 227*20+base and pixel_address <= 227*20+base+1 else
						(others=>'1') when pixel_address >= 228*20+base and pixel_address <= 228*20+base+1 else
						(others=>'1') when pixel_address >= 229*20+base and pixel_address <= 229*20+base+1 else
						(others=>'1') when pixel_address >= 230*20+base and pixel_address <= 230*20+base+1 else
						(others=>'1') when pixel_address >= 231*20+base and pixel_address <= 231*20+base+1 else
						(others=>'1') when pixel_address >= 232*20+base and pixel_address <= 232*20+base+1 else
						(others=>'1') when pixel_address >= 233*20+base and pixel_address <= 233*20+base+1 else
						(others=>'1') when pixel_address >= 234*20+base and pixel_address <= 234*20+base+1 else
						(others=>'1') when pixel_address >= 235*20+base and pixel_address <= 235*20+base+1 else
						(others=>'1') when pixel_address >= 236*20+base and pixel_address <= 236*20+base+1 else
						(others=>'1') when pixel_address >= 237*20+base and pixel_address <= 237*20+base+1 else
						(others=>'1') when pixel_address >= 238*20+base and pixel_address <= 238*20+base+1 else
						(others=>'1') when pixel_address >= 239*20+base and pixel_address <= 239*20+base+1 else
						(others=>'1') when pixel_address >= 240*20+base and pixel_address <= 240*20+base+1 else
						(others=>'1') when pixel_address >= 241*20+base and pixel_address <= 241*20+base+1 else
						(others=>'1') when pixel_address >= 242*20+base and pixel_address <= 242*20+base+1 else
						(others=>'1') when pixel_address >= 243*20+base and pixel_address <= 243*20+base+1 else
						(others=>'1') when pixel_address >= 244*20+base and pixel_address <= 244*20+base+1 else
						(others=>'1') when pixel_address >= 245*20+base and pixel_address <= 245*20+base+1 else
						(others=>'1') when pixel_address >= 246*20+base and pixel_address <= 246*20+base+1 else
						(others=>'1') when pixel_address >= 247*20+base and pixel_address <= 247*20+base+1 else
						(others=>'1') when pixel_address >= 248*20+base and pixel_address <= 248*20+base+1 else
						(others=>'1') when pixel_address >= 249*20+base and pixel_address <= 249*20+base+1 else
						(others=>'1') when pixel_address >= 250*20+base and pixel_address <= 250*20+base+1 else
						(others=>'1') when pixel_address >= 251*20+base and pixel_address <= 251*20+base+1 else
						(others=>'1') when pixel_address >= 252*20+base and pixel_address <= 252*20+base+1 else
						(others=>'1') when pixel_address >= 253*20+base and pixel_address <= 253*20+base+1 else
						(others=>'1') when pixel_address >= 254*20+base and pixel_address <= 254*20+base+1 else
						(others=>'1') when pixel_address >= 255*20+base and pixel_address <= 255*20+base+1 else
						(others=>'1') when pixel_address >= 256*20+base and pixel_address <= 256*20+base+1 else
						(others=>'1') when pixel_address >= 257*20+base and pixel_address <= 257*20+base+1 else
						(others=>'1') when pixel_address >= 258*20+base and pixel_address <= 258*20+base+1 else
						(others=>'1') when pixel_address >= 259*20+base and pixel_address <= 259*20+base+1 else
						(others=>'1') when pixel_address >= 260*20+base and pixel_address <= 260*20+base+1 else
						(others=>'1') when pixel_address >= 261*20+base and pixel_address <= 261*20+base+1 else
						(others=>'1') when pixel_address >= 262*20+base and pixel_address <= 262*20+base+1 else
						(others=>'1') when pixel_address >= 263*20+base and pixel_address <= 263*20+base+1 else
						(others=>'1') when pixel_address >= 264*20+base and pixel_address <= 264*20+base+1 else
						(others=>'1') when pixel_address >= 265*20+base and pixel_address <= 265*20+base+1 else
						(others=>'1') when pixel_address >= 266*20+base and pixel_address <= 266*20+base+1 else
						(others=>'1') when pixel_address >= 267*20+base and pixel_address <= 267*20+base+1 else
						(others=>'1') when pixel_address >= 268*20+base and pixel_address <= 268*20+base+1 else
						(others=>'1') when pixel_address >= 269*20+base and pixel_address <= 269*20+base+1 else
						(others=>'1') when pixel_address >= 270*20+base and pixel_address <= 270*20+base+1 else
						(others=>'1') when pixel_address >= 271*20+base and pixel_address <= 271*20+base+1 else
						(others=>'1') when pixel_address >= 272*20+base and pixel_address <= 272*20+base+1 else
						(others=>'0');
  
  
  
  
end rtl;