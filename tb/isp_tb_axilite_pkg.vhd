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

    -- Sweep of a STATUS flag across the pulse that sets it (test_flag_coincidence): for d = 0 to Steps - 1 waits for
    -- marker Base + d, acknowledges it, writes 1 to bit Bit of the register at StatusAddr d cycles later, reads the
    -- register and checks the flag: set exactly when the pulse came in the first cycle of BVALID of the write or
    -- later. PulseCyc and BValidCyc are the cycles of the last pulse and of the first cycle of the last BVALID,
    -- recorded by the testbench. Fails unless the sweep has steps before, at and after the pulse.
    procedure ispFlagSweep (
        constant Base       : natural;
        constant Steps      : positive;
        constant StatusAddr : natural;
        constant Bit        : natural;
        constant Name       : string;
        constant ClkPeriod  : time;
        signal   Marker     : in    natural;
        signal   Ack        : out   natural;
        signal   PulseCyc   : in    natural;
        signal   BValidCyc  : in    natural;
        signal   Clk        : in    std_logic;
        signal   Axi        : inout t_axilite_if);

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
        variable Addr_v    : unsigned(Axi.write_address_channel.awaddr'length - 1 downto 0);
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
            Op_v := W_v(1);
            readWord(L_v, W_v, Len_v);
            -- The address in the width of the bus (hexToSlv stops at an address that does not fit)
            Addr_v := unsigned(hexToSlv(W_v(1 to Len_v), Axi.write_address_channel.awaddr'length));
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

    procedure ispFlagSweep (
        constant Base       : natural;
        constant Steps      : positive;
        constant StatusAddr : natural;
        constant Bit        : natural;
        constant Name       : string;
        constant ClkPeriod  : time;
        signal   Marker     : in    natural;
        signal   Ack        : out   natural;
        signal   PulseCyc   : in    natural;
        signal   BValidCyc  : in    natural;
        signal   Clk        : in    std_logic;
        signal   Axi        : inout t_axilite_if) is
        constant Cfg_c      : t_axilite_bfm_config                                           := ispAxiConfig(ClkPeriod);
        constant Addr_c     : unsigned(Axi.write_address_channel.awaddr'length - 1 downto 0) :=
            to_unsigned(StatusAddr, Axi.write_address_channel.awaddr'length);
        variable Data_v     : std_logic_vector(31 downto 0);
        variable Clear_v    : std_logic_vector(31 downto 0)                                  := (others => '0');
        variable Expect_v   : std_logic;
        variable Coincide_v : boolean                                                        := false;
        variable Before_v   : boolean                                                        := false;
        variable After_v    : boolean                                                        := false;
    begin
        Clear_v(Bit) := '1';

        for d in 0 to Steps - 1 loop
            if Marker /= Base + d then
                wait until Marker = Base + d;
            end if;
            Ack <= Base + d;

            for i in 1 to d loop
                wait until rising_edge(Clk);
            end loop;

            axilite_write(Addr_c, Clear_v, "clear " & Name & ", step " & integer'image(d), Clk, Axi, config => Cfg_c);

            -- Wait for the pulse of the step, then read the flag
            for i in 1 to 20 loop
                wait until rising_edge(Clk);
            end loop;

            axilite_read(Addr_c, Data_v, "read " & Name & ", step " & integer'image(d), Clk, Axi, config => Cfg_c);
            -- The clear takes effect in the first cycle of BVALID; a pulse in that cycle or later wins
            Expect_v := '0';
            if PulseCyc >= BValidCyc then
                Expect_v := '1';
            end if;
            check_value(Data_v(Bit), Expect_v, ERROR,
                        Name & " after the clear, step " & integer'image(d) & ": pulse in cycle " &
                        integer'image(PulseCyc) & ", clear in cycle " & integer'image(BValidCyc));
            log(ID_SEQUENCER, Name & ", step " & integer'image(d) & ": pulse in cycle " & integer'image(PulseCyc) &
                ", clear in cycle " & integer'image(BValidCyc));
            Coincide_v := Coincide_v or PulseCyc = BValidCyc;
            Before_v   := Before_v or PulseCyc < BValidCyc;
            After_v    := After_v or PulseCyc > BValidCyc;

            -- Clear the flag for the next step
            axilite_write(Addr_c, Clear_v, "clear " & Name, Clk, Axi, config => Cfg_c);
        end loop;

        check_value(Coincide_v and Before_v and After_v, ERROR,
                    Name & ": the sweep has steps before, at and after the pulse");
    end procedure;

end package body;
