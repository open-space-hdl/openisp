---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register script of the OpenISP testbenches: executes the register accesses of a test file at the
-- markers of the stimulus with the AXI4-Lite BFM of UVVM, one access after the other, and
-- acknowledges every marker (docs/testbench.md, section 7).
--
-- What this model does NOT check or reproduce: it does not run accesses in parallel or reorder them;
-- the read and write channels of the slave are exercised one transaction at a time.
--
-- Documentation: docs/testbench.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.textio.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package isp_tb_axilite_pkg is

    -- BFM configuration for a clock of the given period
    function ispAxiConfig (clk_period : time) return t_axilite_bfm_config;

    -- Executes the register script RegsFile: for every marker of the file waits until the source sets it,
    -- performs its accesses and sets Ack to it
    procedure ispRegsRun (
        constant RegsFile  : string;
        constant ClkPeriod : time;
        signal   Marker    : in    natural;
        signal   Ack       : out   natural;
        signal   Clk       : in    std_logic;
        signal   Axi       : inout t_axilite_if);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body isp_tb_axilite_pkg is

    function ispAxiConfig (clk_period : time) return t_axilite_bfm_config is
        variable Cfg_v : t_axilite_bfm_config := C_AXILITE_BFM_CONFIG_DEFAULT;
    begin
        Cfg_v.clock_period := clk_period;
        Cfg_v.setup_time   := clk_period / 4;
        Cfg_v.hold_time    := clk_period / 4;
        return Cfg_v;
    end function;

    procedure ispRegsRun (
        constant RegsFile  : string;
        constant ClkPeriod : time;
        signal   Marker    : in    natural;
        signal   Ack       : out   natural;
        signal   Clk       : in    std_logic;
        signal   Axi       : inout t_axilite_if) is
        variable L_v       : line;
        variable W_v       : string(1 to WordMax_c);
        variable Len_v     : natural;
        variable M_v       : natural;
        variable Prev_v    : natural              := 0;
        variable Started_v : boolean              := false;
        variable Op_v      : character;
        variable Addr_v    : unsigned(31 downto 0);
        variable Data_v    : std_logic_vector(31 downto 0);
        variable Strobe_v  : std_logic_vector(3 downto 0);
        constant Cfg_c     : t_axilite_bfm_config := ispAxiConfig(ClkPeriod);
        file F_v : text;
    begin
        file_open(F_v, RegsFile, read_mode);

        while not endfile(F_v) loop
            readline(F_v, L_v);
            readWord(L_v, W_v, Len_v);
            next when Len_v = 0;
            M_v := decToInt(W_v(1 to Len_v));

            -- A new marker: acknowledge the one before, wait for this one
            if not Started_v or M_v /= Prev_v then
                if Started_v then
                    Ack <= Prev_v;
                end if;
                if Marker /= M_v then
                    wait until Marker = M_v;
                end if;
                Prev_v    := M_v;
                Started_v := true;
            end if;

            readWord(L_v, W_v, Len_v);
            Op_v   := W_v(1);
            readWord(L_v, W_v, Len_v);
            Addr_v := unsigned(hexToSlv(W_v(1 to Len_v), 32));
            readWord(L_v, W_v, Len_v);
            Data_v := hexToSlv(W_v(1 to Len_v), 32);

            case Op_v is

                when 'W' =>
                    readWord(L_v, W_v, Len_v);
                    if Len_v = 0 then
                        Strobe_v := "1111";
                    else
                        Strobe_v := hexToSlv(W_v(1 to Len_v), 4);
                    end if;
                    axilite_write(Addr_v, Data_v, Strobe_v, "register script, marker " & integer'image(M_v), Clk, Axi,
                                  config => Cfg_c);

                when 'C' =>
                    axilite_check(Addr_v, Data_v, "register script, marker " & integer'image(M_v), Clk, Axi,
                                  error, config => Cfg_c);

                when others =>
                    error("register script: unknown operation " & Op_v);

            end case;

        end loop;

        if Started_v then
            Ack <= Prev_v;
        end if;
    end procedure;

end package body;
