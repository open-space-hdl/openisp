---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_pkg: the constants and functions against values that the testbench computes in
-- another way (the bits of n - 1 counted in a loop, the image start from a written-out table).
--
-- * test_package: flag constants, ispPosWidth for n = 1 to 65536, ispIsImageStart for every
--   combination of first beat and flags and for metavalues
--
-- Documentation: hdl/isp_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

architecture sim of isp_pkg_tb is

    type Values_t is array (natural range <>) of std_logic;

    constant Meta_c : Values_t := ('U', 'X', 'Z', 'W', 'L', 'H', '-');

    -- Bits of n - 1, at least 1, counted
    function bitsOf (n : positive) return positive is
        variable V_v : natural  := n - 1;
        variable B_v : positive := 1;
    begin

        while V_v > 1 loop
            V_v := V_v / 2;
            B_v := B_v + 1;
        end loop;

        return B_v;
    end function;

begin

    p_main : process is
        variable Exp_v : boolean;
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop
            if run("test_package") then
                -- PKG-01
                check_value(SeqCont_c, "00", ERROR, "SeqCont_c");
                check_value(SeqFirst_c, "01", ERROR, "SeqFirst_c");
                check_value(SeqLast_c, "10", ERROR, "SeqLast_c");
                check_value(SeqOnly_c, "11", ERROR, "SeqOnly_c");

                -- PKG-02
                for n in 1 to 65536 loop
                    if ispPosWidth(n) /= bitsOf(n) then
                        error("ispPosWidth(" & integer'image(n) & ") = " & integer'image(ispPosWidth(n)) &
                              ", expected " & integer'image(bitsOf(n)));
                    end if;
                end loop;

                -- PKG-03: table of the eight combinations
                for f in std_logic range '0' to '1' loop

                    for u1 in std_logic range '0' to '1' loop

                        for u0 in std_logic range '0' to '1' loop
                            Exp_v := f = '1' and ((u1 = '0' and u0 = '1') or (u1 = '1' and u0 = '1'));
                            check_value(ispIsImageStart(f, u1 & u0), Exp_v, ERROR,
                                        "ispIsImageStart(" & std_logic'image(f) & ", " & std_logic'image(u1) &
                                        std_logic'image(u0) & ")");
                        end loop;

                    end loop;

                end loop;

                -- PKG-03: a metavalue in the first-beat flag or in a flag bit gives false
                for i in Meta_c'range loop
                    check_value(ispIsImageStart(Meta_c(i), "01"), false, ERROR, "metavalue in first");
                    check_value(ispIsImageStart('1', '0' & Meta_c(i)), false, ERROR, "metavalue in user(0)");
                    check_value(ispIsImageStart('1', Meta_c(i) & '1'), false, ERROR, "metavalue in user(1)");
                    check_value(ispIsImageStart(Meta_c(i), "11"), false, ERROR, "metavalue in first, flags 11");
                end loop;

            end if;
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

end architecture;
