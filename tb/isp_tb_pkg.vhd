---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenISP testbenches (VUnit runner plus UVVM).
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

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package isp_tb_pkg is

    -- Ends a test: prints the UVVM alert summary, stops the simulation with a failure when the alert counters
    -- differ from the expected alerts (an unexpected alert or an expected alert that did not occur), whatever the
    -- stop limits of the test, which fails the VUnit test, and hands over to the VUnit runner.
    procedure ispTestEnd (signal runner : inout runner_sync_t);

    -- Longest word of a stimulus or expected file (a window of 16 x 16 pixels of 32 bits in hexadecimal)
    constant WordMax_c : positive := 4096;

    -- Reads the next word of a line, separated by spaces; Len = 0 at the end of the line
    procedure readWord (
        variable L   : inout line;
        variable W   : out string;
        variable Len : out natural);

    -- Hexadecimal word to a vector of Width bits; digits beyond Width must be zero
    function hexToSlv (
        s     : string;
        width : positive) return std_logic_vector;

    -- Decimal word to an integer
    function decToInt (s : string) return integer;

    -- List of decimal integers separated by commas ("3,-1,0") to a vector, element 0 first: a vector generic that
    -- GHDL cannot set on the command line is given to a testbench as a string
    function ispIntList (s : string) return integer_vector;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body isp_tb_pkg is

    procedure ispTestEnd (signal runner : inout runner_sync_t) is
        variable Mismatch_v : boolean := false;
    begin
        report_alert_counters(FINAL);

        -- The alert counters are compared here, for the levels UVVM uses for its end status, so the result does
        -- not depend on when UVVM updates its end status (shared_uvvm_status)
        for L in WARNING to TB_FAILURE loop

            if L /= MANUAL_CHECK and get_alert_counter(L, REGARD) /= get_alert_counter(L, EXPECT) then
                Mismatch_v := true;
                log(ID_SEQUENCER, t_alert_level'image(L) & ": " & integer'image(get_alert_counter(L, REGARD))
                                  & " alerts, " & integer'image(get_alert_counter(L, EXPECT)) & " expected",
                    "ispTestEnd");
            end if;

        end loop;

        -- A failure ends the simulation, whatever the stop limits of the test
        assert not Mismatch_v
            report "ispTestEnd: the alerts of the test differ from the expected alerts (summary above)"
            severity failure;
        test_runner_cleanup(runner);
    end procedure;

    procedure readWord (
        variable L   : inout line;
        variable W   : out string;
        variable Len : out natural) is
        variable C_v : character;
        variable N_v : natural := 0;
    begin
        W := (W'range => ' ');

        -- Spaces before the word
        while L /= null and L'length > 0 loop
            exit when L(L'left) /= ' ' and L(L'left) /= HT;
            read(L, C_v);
        end loop;

        while L /= null and L'length > 0 loop
            exit when L(L'left) = ' ' or L(L'left) = HT or L(L'left) = CR;
            read(L, C_v);
            assert N_v < W'length
                report "readWord: word longer than " & integer'image(W'length) & " characters"
                severity failure;
            W(W'left + N_v) := C_v;
            N_v             := N_v + 1;
        end loop;

        Len := N_v;
    end procedure;

    function hexToSlv (
        s     : string;
        width : positive) return std_logic_vector is
        variable Full_v  : std_logic_vector(4 * s'length - 1 downto 0);
        variable Digit_v : natural;
        variable Res_v   : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin

        for i in 0 to s'length - 1 loop

            case s(s'left + i) is
                when '0' to '9' => Digit_v := character'pos(s(s'left + i)) - character'pos('0');
                when 'a' to 'f' => Digit_v := character'pos(s(s'left + i)) - character'pos('a') + 10;
                when 'A' to 'F' => Digit_v := character'pos(s(s'left + i)) - character'pos('A') + 10;
                when others =>
                    report "hexToSlv: '" & s & "' is not a hexadecimal number"
                        severity failure;
            end case;

            Full_v(4 * (s'length - i) - 1 downto 4 * (s'length - i - 1)) := std_logic_vector(to_unsigned(Digit_v, 4));
        end loop;

        for b in 0 to Full_v'length - 1 loop
            if b < width then
                Res_v(b) := Full_v(b);
            else
                assert Full_v(b) = '0'
                    report "hexToSlv: '" & s & "' does not fit in " & integer'image(width) & " bits"
                    severity failure;
            end if;
        end loop;

        return Res_v;
    end function;

    function decToInt (s : string) return integer is
    begin
        return integer'value(s);
    end function;

    function ispIntList (s : string) return integer_vector is
        function count (str : string) return positive is
            variable N_v : positive := 1;
        begin

            for i in str'range loop
                if str(i) = ',' then
                    N_v := N_v + 1;
                end if;
            end loop;

            return N_v;
        end function;

        variable Res_v   : integer_vector(0 to count(s) - 1);
        variable Start_v : integer := s'left;
        variable K_v     : natural := 0;
    begin

        for i in s'left to s'right + 1 loop
            if i > s'right or s(i) = ',' then
                assert i > Start_v
                    report "ispIntList: empty element in '" & s & "'"
                    severity failure;
                Res_v(K_v) := integer'value(s(Start_v to i - 1));
                K_v        := K_v + 1;
                Start_v    := i + 1;
            end if;
        end loop;

        return Res_v;
    end function;

end package body;
