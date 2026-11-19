---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Pixel stream source of the OpenISP testbenches: reads a stimulus file and drives the input of a
-- module. Entries: B beat, G pause, W wait for the sink, T wait cycles, P probe a status, H hold the
-- sink, M marker, K wait for the register script, R reset (docs/testbench.md, section 3). Random pauses of 1 to 4 cycles before a
-- beat with the probability GapPct_g; data, Last and User are 'X' while Valid is low.
--
-- What this model does NOT check or reproduce: it does not check the handshake of the module beyond
-- waiting for ready; it sends the beats of the file as they are, so malformed streams come only from
-- the file.
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
entity isp_tb_source is
    generic (
        Width_g      : positive;
        StimFile_g   : string;
        GapPct_g     : natural  := 0;
        Seed_g       : positive := 1;
        ProbeWidth_g : positive := 1
    );
    port (
        Clk       : in    std_logic;
        Rst       : in    std_logic;
        M_Valid   : out   std_logic;
        M_Ready   : in    std_logic;
        M_Data    : out   std_logic_vector(Width_g - 1 downto 0);
        M_Last    : out   std_logic;
        M_User    : out   std_logic_vector(1 downto 0);
        SinkCount : in    natural;
        Probe     : in    std_logic_vector(ProbeWidth_g - 1 downto 0);
        RstReq    : out   std_logic;
        Hold      : out   std_logic;
        Marker    : out   natural;
        Ack       : in    natural := 0;
        Done      : out   boolean
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of isp_tb_source is

begin

    p_source : process is
        variable L_v      : line;
        variable W_v      : string(1 to WordMax_c);
        variable Len_v    : natural;
        variable Entry_v  : natural  := 0;
        variable N_v      : natural;
        variable Cycles_v : natural;
        variable Data_v   : std_logic_vector(Width_g - 1 downto 0);
        variable Last_v   : std_logic;
        variable User_v   : std_logic_vector(1 downto 0);
        variable Seed1_v  : positive := 13 + Seed_g mod 1000000;
        variable Seed2_v  : positive := 977 + 7 * (Seed_g mod 1000000);
        variable Rand_v   : real;

        procedure idle is
        begin
            M_Valid <= '0';
            M_Data  <= (others => 'X');
            M_Last  <= 'X';
            M_User  <= (others => 'X');
        end procedure;

        procedure cycles (n : natural) is
        begin

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        procedure nextNumber (variable n : out natural) is
        begin
            readWord(L_v, W_v, Len_v);
            n := decToInt(W_v(1 to Len_v));
        end procedure;

        file F_v : text;
    begin
        idle;
        RstReq <= '0';
        Hold   <= '0';
        Marker <= 0;
        Done   <= false;
        file_open(F_v, StimFile_g, read_mode);

        -- Start after the first reset
        wait until rising_edge(Clk) and Rst = '0';

        while not endfile(F_v) loop
            readline(F_v, L_v);
            readWord(L_v, W_v, Len_v);
            next when Len_v = 0;
            Entry_v := Entry_v + 1;

            case W_v(1) is

                when 'B' =>
                    readWord(L_v, W_v, Len_v);
                    Data_v := hexToSlv(W_v(1 to Len_v), Width_g);
                    nextNumber(N_v);
                    Last_v := '1' when N_v = 1 else '0';
                    nextNumber(N_v);
                    User_v := std_logic_vector(to_unsigned(N_v, 2));

                    -- Random pause before the beat
                    uniform(Seed1_v, Seed2_v, Rand_v);
                    if Rand_v * 100.0 < real(GapPct_g) then
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        idle;
                        cycles(1 + integer(floor(Rand_v * 3.999)));
                    end if;

                    M_Valid <= '1';
                    M_Data  <= Data_v;
                    M_Last  <= Last_v;
                    M_User  <= User_v;

                    loop
                        wait until rising_edge(Clk);
                        exit when M_Ready = '1';
                    end loop;

                    idle;

                when 'G' =>
                    nextNumber(N_v);
                    idle;
                    cycles(N_v);

                when 'T' =>
                    nextNumber(N_v);
                    cycles(N_v);

                when 'W' =>
                    nextNumber(N_v);

                    while SinkCount < N_v loop
                        wait until rising_edge(Clk);
                    end loop;

                when 'P' =>
                    readWord(L_v, W_v, Len_v);
                    check_value(Probe, hexToSlv(W_v(1 to Len_v), ProbeWidth_g), ERROR,
                                "probe of stimulus entry " & integer'image(Entry_v));

                when 'H' =>
                    nextNumber(N_v);
                    Hold <= '1' when N_v = 1 else '0';

                when 'M' =>
                    nextNumber(N_v);
                    Marker <= N_v;

                when 'K' =>
                    nextNumber(N_v);

                    while Ack < N_v loop
                        wait until rising_edge(Clk);
                    end loop;

                when 'R' =>
                    nextNumber(N_v);
                    readWord(L_v, W_v, Len_v);
                    nextNumber(Cycles_v);

                    while SinkCount < N_v loop
                        wait until rising_edge(Clk);
                    end loop;

                    RstReq <= '1';
                    cycles(Cycles_v);
                    RstReq <= '0';

                when others =>
                    error("stimulus entry " & integer'image(Entry_v) & ": unknown kind " & W_v(1));

            end case;

        end loop;

        idle;
        Done <= true;
        wait;
    end process;

end architecture;
