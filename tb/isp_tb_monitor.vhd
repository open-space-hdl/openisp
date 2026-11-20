---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Contract monitor of the OpenISP testbenches: observes a pixel stream without driving it and
-- checks the contract of an output stream: Last on every Width_g-th beat of an image, the sequence
-- flags of the lines ("01" first, "10" last, "11" for an image of one line, "00" otherwise), the
-- same flags on every beat of a packet, and Height_g packets per image. A reset restarts it; beats
-- while Skip is true are not checked (a running reset of the sink). The sink uses it for the output
-- of a module, the chain test on every connection between two modules.
--
-- Documentation: docs/testbench.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_tb_monitor is
    generic (
        Width_g  : positive;
        Height_g : positive;
        -- Name of the stream in the messages
        Name_g   : string := "contract"
    );
    port (
        Clk     : in    std_logic;
        Rst     : in    std_logic;
        S_Valid : in    std_logic;
        S_Ready : in    std_logic;
        S_Last  : in    std_logic;
        S_User  : in    std_logic_vector(1 downto 0);
        Skip    : in    boolean := false
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of isp_tb_monitor is

begin

    p_contract : process (Clk) is
        variable InImage_v  : boolean                      := false;
        variable Lines_v    : natural                      := 0;
        variable Beats_v    : natural                      := 0;
        variable FirstPkt_v : boolean                      := true;
        variable Flags_v    : std_logic_vector(1 downto 0) := "00";
        variable Exp_v      : std_logic_vector(1 downto 0);
    begin
        if rising_edge(Clk) then
            if Rst = '1' then
                InImage_v  := false;
                Lines_v    := 0;
                Beats_v    := 0;
                FirstPkt_v := true;
            elsif S_Valid = '1' and S_Ready = '1' and not Skip then
                if FirstPkt_v then
                    if not InImage_v then
                        InImage_v := true;
                        Lines_v   := 0;
                    end if;
                    if Height_g = 1 then
                        Exp_v := "11";
                    elsif Lines_v = 0 then
                        Exp_v := "01";
                    elsif Lines_v = Height_g - 1 then
                        Exp_v := "10";
                    else
                        Exp_v := "00";
                    end if;
                    if S_User /= Exp_v then
                        error(Name_g & ": line " & integer'image(Lines_v) & " starts with the flags " &
                              to_string(S_User) & ", expected " & to_string(Exp_v));
                    end if;
                    Flags_v := S_User;
                elsif S_User /= Flags_v then
                    error(Name_g & ": flags " & to_string(S_User) & " within a packet with the flags " &
                          to_string(Flags_v));
                end if;

                Beats_v := Beats_v + 1;
                if S_Last = '1' then
                    if Beats_v /= Width_g then
                        error(Name_g & ": line " & integer'image(Lines_v) & " of " & integer'image(Beats_v) &
                              " beats, expected " & integer'image(Width_g));
                    end if;
                    Beats_v    := 0;
                    Lines_v    := Lines_v + 1;
                    FirstPkt_v := true;
                    if Lines_v = Height_g then
                        InImage_v := false;
                    end if;
                else
                    if Beats_v >= Width_g then
                        error(Name_g & ": no Last on beat " & integer'image(Beats_v) & " of line " &
                              integer'image(Lines_v));
                    end if;
                    FirstPkt_v := false;
                end if;
            end if;
        end if;
    end process;

end architecture;
