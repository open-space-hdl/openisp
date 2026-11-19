---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Pixel stream sink of the OpenISP testbenches: takes the output of a module with random stalls of
-- 1 to 4 cycles (StallPct_g) and compares every beat and its sideband with the expected file; a beat
-- after the last expected one is an error. Its contract checker verifies the output contract of the
-- pixel stream independent of the file: Last on every OutWidth_g-th beat of an image, the flags
-- constant within a packet, the flags in the order "01", "00", "10" ("11" for one line) and
-- OutHeight_g packets per image. Reset entries: held (Ready low from the entry to the reset) or
-- running (beats taken without comparison until the reset); both restart the contract checker.
--
-- What this model does NOT check or reproduce: it does not check the stability of a beat that the
-- sink does not take in the same cycle (AXI4-Stream rule); it does not check the timing of the beats.
--
-- Documentation: docs/testbench.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library std;
    use std.textio.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_tb_sink is
    generic (
        Width_g     : positive;
        SideWidth_g : positive := 1;
        ExpFile_g   : string;
        StallPct_g  : natural  := 0;
        Seed_g      : positive := 1;
        OutWidth_g  : positive;
        OutHeight_g : positive;
        Contract_g  : boolean  := true
    );
    port (
        Clk     : in    std_logic;
        Rst     : in    std_logic;
        S_Valid : in    std_logic;
        S_Ready : out   std_logic;
        S_Data  : in    std_logic_vector(Width_g - 1 downto 0);
        S_Last  : in    std_logic;
        S_User  : in    std_logic_vector(1 downto 0);
        S_Side  : in    std_logic_vector(SideWidth_g - 1 downto 0) := (others => '0');
        Hold    : in    std_logic                                  := '0';
        Count   : out   natural;
        Done    : out   boolean
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of isp_tb_sink is

    signal ReadyInt : std_logic := '0';
    -- Beats are taken without comparison (running reset)
    signal Skip     : boolean := false;

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        end if;
        return '0';
    end function;

begin

    S_Ready <= ReadyInt and not Hold;

    -----------------------------------------------------------------------------------------------
    -- Comparison with the expected file
    -----------------------------------------------------------------------------------------------
    p_compare : process is
        variable L_v     : line;
        variable W_v     : string(1 to WordMax_c);
        variable Len_v   : natural;
        variable N_v     : natural;
        variable Count_v : natural  := 0;
        variable Data_v  : std_logic_vector(Width_g - 1 downto 0);
        variable Last_v  : std_logic;
        variable User_v  : std_logic_vector(1 downto 0);
        variable Side_v  : std_logic_vector(SideWidth_g - 1 downto 0);
        variable Seed1_v : positive := 31 + Seed_g mod 1000000;
        variable Seed2_v : positive := 1009 + 11 * (Seed_g mod 1000000);
        variable Rand_v  : real;

        -- Random stall of 1 to 4 cycles with the probability StallPct_g
        procedure maybeStall is
        begin
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Rand_v * 100.0 < real(StallPct_g) then
                uniform(Seed1_v, Seed2_v, Rand_v);
                ReadyInt <= '0';

                for i in 1 to 1 + integer(floor(Rand_v * 3.999)) loop
                    wait until rising_edge(Clk);
                end loop;

            end if;
        end procedure;

        procedure nextNumber (variable n : out natural) is
        begin
            readWord(L_v, W_v, Len_v);
            n := decToInt(W_v(1 to Len_v));
        end procedure;

        file F_v : text;
    begin
        Count <= 0;
        Done  <= false;
        file_open(F_v, ExpFile_g, read_mode);
        wait until rising_edge(Clk) and Rst = '0';

        while not endfile(F_v) loop
            readline(F_v, L_v);
            readWord(L_v, W_v, Len_v);
            next when Len_v = 0;

            case W_v(1) is

                when 'B' =>
                    readWord(L_v, W_v, Len_v);
                    Data_v := hexToSlv(W_v(1 to Len_v), Width_g);
                    nextNumber(N_v);
                    Last_v := '1' when N_v = 1 else '0';
                    nextNumber(N_v);
                    User_v := std_logic_vector(to_unsigned(N_v, 2));
                    readWord(L_v, W_v, Len_v);
                    Side_v := hexToSlv(W_v(1 to Len_v), SideWidth_g);

                    maybeStall;
                    ReadyInt <= '1';

                    loop
                        wait until rising_edge(Clk);
                        exit when S_Valid = '1' and S_Ready = '1';
                    end loop;

                    if S_Data /= Data_v or S_Last /= Last_v or S_User /= User_v or S_Side /= Side_v then
                        error("beat " & integer'image(Count_v) & ": expected data " & to_hstring(Data_v) &
                              " last " & std_logic'image(Last_v) & " user " & to_string(User_v) &
                              " side " & to_hstring(Side_v) & ", received data " & to_hstring(S_Data) &
                              " last " & std_logic'image(S_Last) & " user " & to_string(S_User) &
                              " side " & to_hstring(S_Side));
                    end if;
                    Count_v := Count_v + 1;
                    Count   <= Count_v;

                when 'R' =>
                    nextNumber(N_v);
                    if N_v = 0 then
                        -- Held: no beat until the reset
                        ReadyInt <= '0';

                        loop
                            wait until rising_edge(Clk);
                            exit when Rst = '1';
                        end loop;

                    else
                        -- Running: beats taken without comparison until the reset
                        Skip <= true;

                        loop
                            uniform(Seed1_v, Seed2_v, Rand_v);
                            ReadyInt <= toSl(Rand_v * 100.0 >= real(StallPct_g));
                            wait until rising_edge(Clk);
                            exit when Rst = '1';
                        end loop;

                    end if;

                    ReadyInt <= '0';

                    loop
                        wait until rising_edge(Clk);
                        exit when Rst = '0';
                    end loop;

                    Skip <= false;

                when others =>
                    error("expected file: unknown kind " & W_v(1));

            end case;

        end loop;

        -- Every expected beat received: a further beat is an error
        Done     <= true;
        ReadyInt <= '1';

        loop
            wait until rising_edge(Clk);
            if S_Valid = '1' and S_Ready = '1' then
                error("beat after the last expected beat: data " & to_hstring(S_Data));
            end if;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Contract checker
    -----------------------------------------------------------------------------------------------
    g_contract : if Contract_g generate

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
                        if OutHeight_g = 1 then
                            Exp_v := "11";
                        elsif Lines_v = 0 then
                            Exp_v := "01";
                        elsif Lines_v = OutHeight_g - 1 then
                            Exp_v := "10";
                        else
                            Exp_v := "00";
                        end if;
                        if S_User /= Exp_v then
                            error("contract: line " & integer'image(Lines_v) & " starts with the flags " &
                                  to_string(S_User) & ", expected " & to_string(Exp_v));
                        end if;
                        Flags_v := S_User;
                    elsif S_User /= Flags_v then
                        error("contract: flags " & to_string(S_User) & " within a packet with the flags " &
                              to_string(Flags_v));
                    end if;

                    Beats_v := Beats_v + 1;
                    if S_Last = '1' then
                        if Beats_v /= OutWidth_g then
                            error("contract: line " & integer'image(Lines_v) & " of " & integer'image(Beats_v) &
                                  " beats, expected " & integer'image(OutWidth_g));
                        end if;
                        Beats_v    := 0;
                        Lines_v    := Lines_v + 1;
                        FirstPkt_v := true;
                        if Lines_v = OutHeight_g then
                            InImage_v := false;
                        end if;
                    else
                        if Beats_v >= OutWidth_g then
                            error("contract: no Last on beat " & integer'image(Beats_v) & " of line " &
                                  integer'image(Lines_v));
                        end if;
                        FirstPkt_v := false;
                    end if;
                end if;
            end if;
        end process;

    end generate;

end architecture;
