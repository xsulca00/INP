-- cpu.vhd: Simple 8-bit CPU (BrainLove interpreter)
-- Copyright (C) 2016 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): DOPLNIT
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

 -- zde dopiste potrebne deklarace signalu  
          
    type fsm_state is (sidle, sinst_null, sfetch0, sdecode, sincptr,
                        sdecptr, sincval0, sincval1, sdecval0, sdecval1,
                        sprintval0, sprintval1, sgetval0, sgetval1, sstoretmp0,
                        sstoretmp1, sloadtmp, swhilebeg0, swhilebeg1, swhilebeg2, swhilebeg3,  swhileend0, swhileend1, swhileend2, swhileend3, swhileend4, spcinc);

    type inst_type is (inc_ptr, dec_ptr, inc_val, dec_val, print_val, get_val, 
                        store_tmp, load_tmp, inst_null, while_beg, while_end, inst_pcinc);
                   
    signal pstate   :   fsm_state;
    signal nstate   :   fsm_state;
 
    signal ins_dec  :   inst_type;
    
    signal pc_inc   :   std_logic; 
    signal pc_dec   :   std_logic;
    signal pc_reg   :   std_logic_vector(11 downto 0);
    
    signal cnt_inc  :   std_logic; 
    signal cnt_dec  :   std_logic;
    signal cnt_reg  :   std_logic_vector(7 downto 0);
    signal cnt_set_one : std_logic;
    
    signal tmp_ld   :   std_logic; 
    signal tmp_reg  :   std_logic_vector(7 downto 0);
    
    signal ptr_inc  :   std_logic; 
    signal ptr_dec  :   std_logic;
    signal ptr_reg  :   std_logic_vector(9 downto 0);
    
    signal data_wdata_mx    :   std_logic_vector(7 downto 0);
    signal data_wdata_mx_sel    :   std_logic_vector(1 downto 0);
    
    signal data_rdata_is_zero  :   std_logic;
    signal cnt_is_zero  :   std_logic;

begin

    -- I/
    OUT_DATA <= DATA_RDATA;    

    pc: process (RESET, CLK)
    begin
        if (RESET='1') then
            pc_reg <= (others => '0');
        elsif (CLK'event) and (CLK='1') then
            if (pc_inc = '1') then
                pc_reg <= pc_reg + 1;
            elsif (pc_dec = '1') then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;
    
    CODE_ADDR <= pc_reg;    
    
    cnt: process (RESET, CLK)
    begin
        if (RESET='1') then
            cnt_reg <= (others => '0');
        elsif (CLK'event) and (CLK='1') then
		if (cnt_set_one = '1') then
	    	cnt_reg <= "00000001";
	end if;
            if (cnt_inc = '1') then
                cnt_reg <= cnt_reg + 1;
            elsif (cnt_dec = '1') then
                cnt_reg <= cnt_reg - 1;
            end if;
        end if;
    end process;
    
    tmp: process (RESET, CLK)
    begin
        if (RESET='1') then
            tmp_reg <= (others => '0');
        elsif (CLK'event) and (CLK='1') then
            if (tmp_ld = '1') then
                tmp_reg <= DATA_RDATA;
            end if;
        end if;
    end process;
    
    
    ptr: process (RESET, CLK)
    begin
        if (RESET='1') then
            ptr_reg <= (others => '0');
        elsif (CLK'event) and (CLK='1') then
            if (ptr_inc = '1') then
                ptr_reg <= ptr_reg + 1;
            elsif (ptr_dec = '1') then
                ptr_reg <= ptr_reg - 1;
            end if;       
        end if;
    end process;
    
    DATA_ADDR <= ptr_reg;     
    
    data_wdata_mx <= IN_DATA when data_wdata_mx_sel ="00" else
             tmp_reg when data_wdata_mx_sel ="01" else
             DATA_RDATA + "11111111"  when data_wdata_mx_sel ="10" else
             DATA_RDATA + "00000001";
    
    DATA_WDATA <= data_wdata_mx;
    
    
    cnt_is_zero <= '1' when cnt_reg = "00000000" else '0';
    data_rdata_is_zero <= '1' when DATA_RDATA = "00000000" else '0';

    
    
   -- =================================================================
   -- Instruction decoder (DEC)
   -- =================================================================
                   
   dec: process (CODE_DATA)
   begin
      case (CODE_DATA(7 downto 0)) is 
         when "00111110" => ins_dec <= inc_ptr; -- >
         when "00111100" => ins_dec <= dec_ptr; -- <
         when "00101011" => ins_dec <= inc_val; -- +
         when "00101101" => ins_dec <= dec_val; -- -
         when "00101110" => ins_dec <= print_val; -- .
         when "00101100" => ins_dec <= get_val; -- ,
         when "01011011" => ins_dec <= while_beg; -- [
         when "01011101" => ins_dec <= while_end; -- ]
         when "00100100" => ins_dec <= store_tmp; -- $
         when "00100001" => ins_dec <= load_tmp; -- !
         when "00000000" => ins_dec <= inst_null;
         when others => ins_dec <= inst_pcinc;
      end case;
   end process;
    
   -- =================================================================
   -- FSM present state
   -- =================================================================
   fsm_pstate: process(RESET, CLK)
   begin
      if (RESET='1') then
         pstate <= sidle;
      elsif (CLK'event) and (CLK='1') then
         if (EN = '1') then
            pstate <= nstate;
         end if;
      end if;
   end process;
   
    -- =================================================================
    -- FSM next state logic, Output logic (Moore FSM)
    -- =================================================================
    nsl: process(IN_VLD, IN_DATA, DATA_RDATA, pstate, ins_dec, data_rdata_is_zero, cnt_is_zero, CODE_DATA, OUT_BUSY)
    begin
        nstate <= sidle;

      CODE_EN           <= '0';   
      DATA_RDWR         <= '1';
      DATA_EN           <= '0';
      IN_REQ            <= '0';                  
      OUT_WE            <= '0';                      
      pc_inc            <= '0';
      pc_dec            <= '0';    
      cnt_inc           <= '0'; 
      cnt_dec           <= '0';
      cnt_set_one	<= '0';
      tmp_ld            <= '0';     
      ptr_inc           <= '0';
      ptr_dec           <= '0';    
      data_wdata_mx_sel <= "11";

      case pstate is
         -- IDLE
         when sidle =>
            nstate <= sfetch0;

         -- INSTRUCTION FETCH
         when sfetch0 =>
            nstate <= sdecode;
            CODE_EN <= '1';

         -- INSTRUCTION DECODE
         when sdecode =>
            case ins_dec is
               when inst_null =>
                  nstate <= sinst_null;

	       when inst_pcinc =>
		  nstate <= spcinc;

               when inc_ptr =>
                  nstate <= sincptr;

               when dec_ptr =>
                  nstate <= sdecptr;

               when inc_val =>
                  nstate <= sincval0;
                  
               when dec_val =>
                  nstate <= sdecval0;
                
               when print_val =>
                  nstate <= sprintval0;
            
               when get_val =>
                  nstate <= sgetval0;
                  
               when store_tmp =>
                  nstate <= sstoretmp0;
                
               when load_tmp =>
                  nstate <= sloadtmp;
	       
      	       when while_beg =>
      		  nstate <= swhilebeg0;
      
      	       when while_end =>
      		  nstate <= swhileend0;
         end case;

 	 when spcinc =>
	    nstate <= sfetch0;
	    pc_inc <= '1'; 
        
         --  NULL
         when sinst_null  =>
            nstate <= sinst_null;
            
         --  >
         when sincptr  =>
            nstate <= sfetch0;
            ptr_inc <= '1';    
            pc_inc  <= '1';
            
         --  <
         when sdecptr  =>
            nstate <= sfetch0;
            ptr_dec <= '1';  
            pc_inc <= '1';            
              
         --  +
         when sincval0  =>
            nstate <= sincval1;  -- phase 0
            DATA_EN <= '1';
            DATA_RDWR <= '1';
        
          when sincval1  =>
            nstate <= sfetch0;  -- phase 1
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            data_wdata_mx_sel <= "11";
            pc_inc <= '1';
            
         --  -
         when sdecval0  =>
            nstate <= sdecval1;  -- phase 0
            DATA_EN <= '1';
            DATA_RDWR <= '1';
        
         when sdecval1  =>
            nstate <= sfetch0;  -- phase 1
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            data_wdata_mx_sel <= "10";
            pc_inc <= '1';
            
         -- .
         when sprintval0 =>
            nstate <= sprintval1;   -- phase 0
            DATA_RDWR <= '1';
            DATA_EN <= '1';
            
         when sprintval1 =>
            nstate <= sprintval1;
            if (OUT_BUSY = '0') then    -- phase 1
                nstate <= sfetch0;
                OUT_WE <= '1';
                pc_inc <= '1';         
            end if;
        
         -- ,
         when sgetval0 =>
            nstate <= sgetval1; -- phase 0
            IN_REQ <= '1';
                        
         when sgetval1 =>
            nstate <= sgetval1;     -- phase 1  
	    IN_REQ <= '1';
            if (IN_VLD = '1') then
		nstate <= sfetch0;
                data_wdata_mx_sel <= "00";
                DATA_RDWR <= '0';
                DATA_EN <= '1';
                pc_inc <= '1';
            end if;
         
         -- $
         when sstoretmp0 =>
            nstate <= sstoretmp1;   -- phase 0
            DATA_RDWR <= '1';
            DATA_EN <= '1';
            
         when sstoretmp1 =>
            nstate <= sfetch0;  -- phase 1
            tmp_ld <= '1';
            pc_inc <= '1';
        
        -- !
         when sloadtmp =>
            nstate <= sfetch0;
            DATA_RDWR <= '0';
            DATA_EN <= '1';
            data_wdata_mx_sel <= "01";
            pc_inc <= '1';

    	when swhilebeg0 =>
	     nstate <= swhilebeg1;	
	     DATA_RDWR <= '1';
	     DATA_EN <= '1';
	     pc_inc <= '1';

	when swhilebeg1 =>
	     nstate <= sfetch0;
	     if (data_rdata_is_zero = '1') then
		      nstate <= swhilebeg2;
		      CODE_EN <= '1';
		      cnt_set_one <= '1';
	     end if;
       
	when swhilebeg2 =>
	     nstate <= sfetch0;
	     if (cnt_is_zero = '0') then --  CODE_DATA == '['
		pc_inc <= '1';
		if (ins_dec = while_beg) then
			cnt_inc <= '1';
		elsif (ins_dec = while_end) then
			cnt_dec <= '1';
		end if;
		nstate <= swhilebeg3;          
	     end if;

	 when swhilebeg3 =>
		 CODE_EN <= '1';
		 nstate <= swhilebeg2;



     when swhileend0 =>
	     nstate <= swhileend1;
	     DATA_RDWR <= '1';
	     DATA_EN <= '1';
	     
     when swhileend1 =>
	     nstate <= sfetch0;
	     if (data_rdata_is_zero = '1') then
		     pc_inc <= '1';
	     else
		     cnt_set_one <= '1';
		     pc_dec <= '1';
		     nstate <= swhileend2;
	    end if;

     when swhileend2 =>
	     nstate <= swhileend3;
	     CODE_EN <= '1';

	when swhileend3 =>
		nstate <= sfetch0;
		if (cnt_is_zero = '0') then 
			if (ins_dec = while_beg) then
				cnt_dec <= '1';
			elsif (ins_dec = while_end) then
				cnt_inc <= '1';
			end if;
			nstate <= swhileend4;
		end if;

	when swhileend4 =>
		nstate <= swhileend2;
		if (cnt_is_zero = '1') then
			pc_inc <= '1';
		else
			pc_dec <= '1';
		end if;
	end case;
   end process;

end behavioral;
 
