---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Injection script of the OpenISP testbenches: drives the error injection ports (ErrInj_BitFlip,
-- ErrInj_Valid) and the scrubber enable of a module at the markers of the stimulus and
-- acknowledges every marker (docs/testbench.md, section 8).
--
-- What this model does NOT check or reproduce: it does not observe the module; the effect of an
-- injection is checked by the model and the sink.
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

library work;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_tb_inject is
    generic (
        InjFile_g      : string;
        FlipWidth_g    : positive;
        ScrubDefault_g : std_logic := '1'
    );
    port (
        Clk            : in    std_logic;
        Marker         : in    natural;
        Ack            : out   natural                                    := 0;
        ErrInj_BitFlip : out   std_logic_vector(FlipWidth_g - 1 downto 0) := (others => '0');
        ErrInj_Valid   : out   std_logic                                  := '0';
        Scrub_Enable   : out   std_logic                                  := ScrubDefault_g
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of isp_tb_inject is

begin

    p_inject : process is
        variable L_v       : line;
        variable W_v       : string(1 to WordMax_c);
        variable Len_v     : natural;
        variable M_v       : natural;
        variable Prev_v    : natural := 0;
        variable Started_v : boolean := false;
        variable Op_v      : character;

        file F_v : text;
    begin
        file_open(F_v, InjFile_g, read_mode);

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
            Op_v := W_v(1);
            readWord(L_v, W_v, Len_v);

            case Op_v is

                when 'J' =>
                    -- One cycle of ErrInj_Valid latches the pattern for the next write of the memory
                    wait until rising_edge(Clk);
                    ErrInj_BitFlip <= hexToSlv(W_v(1 to Len_v), FlipWidth_g);
                    ErrInj_Valid   <= '1';
                    wait until rising_edge(Clk);
                    ErrInj_BitFlip <= (others => '0');
                    ErrInj_Valid   <= '0';

                when 'S' =>
                    wait until rising_edge(Clk);
                    Scrub_Enable <= '1' when decToInt(W_v(1 to Len_v)) /= 0 else '0';

                when others =>
                    error("injection script: unknown operation " & Op_v);

            end case;

        end loop;

        if Started_v then
            Ack <= Prev_v;
        end if;
        wait;
    end process;

end architecture;
