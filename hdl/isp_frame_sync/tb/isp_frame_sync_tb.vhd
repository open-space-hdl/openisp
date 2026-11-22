---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_frame_sync: the shared source sends the stimulus file of the test, the shared
-- sink compares the output and its position with the expected file of the reference model and
-- checks the output contract. The testbench counts the Err_Framing pulses, monitors the control
-- outputs for metavalues and their state after every reset, and checks the timing of test_rate.
--
-- * test_images, test_short_images, test_excess_pixels, test_end_flags, test_reset, test_status,
--   test_random_streams: the stimulus of the test against the model
-- * test_rate: in addition the throughput, latency and padding time (markers 1, 1000 + m, 4)
--
-- Documentation: hdl/isp_frame_sync/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

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
entity isp_frame_sync_tb is
    generic (
        runner_cfg    : string;
        ImageWidth_g  : positive := 5;
        ImageHeight_g : positive := 4;
        PixelBits_g   : positive := 12;
        StimFile_g    : string;
        ExpFile_g     : string;
        GapPct_g      : natural  := 0;
        StallPct_g    : natural  := 0;
        Seed_g        : positive := 1;
        -- Number of Err_Framing pulses of the model
        ExpFraming_g  : natural  := 0;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g  : positive := 1000
    );
end entity;

architecture sim of isp_frame_sync_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant XW_c        : positive := ispPosWidth(ImageWidth_g);
    constant YW_c        : positive := ispPosWidth(ImageHeight_g);
    -- Drain time of the test end: latency 2 + 21 (docs/testbench.md, section 6)
    constant Drain_c     : positive := 2 + 21;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic;
    signal InitRst : std_logic := '1';
    signal RstReq  : std_logic;

    signal In_Valid       : std_logic;
    signal In_Ready       : std_logic;
    signal In_Data        : std_logic_vector(PixelBits_g - 1 downto 0);
    signal In_Last        : std_logic;
    signal In_User        : std_logic_vector(1 downto 0);
    signal Out_Valid      : std_logic;
    signal Out_Ready      : std_logic;
    signal Out_Data       : std_logic_vector(PixelBits_g - 1 downto 0);
    signal Out_Last       : std_logic;
    signal Out_User       : std_logic_vector(1 downto 0);
    signal Out_PosX       : std_logic_vector(XW_c - 1 downto 0);
    signal Out_PosY       : std_logic_vector(YW_c - 1 downto 0);
    signal Err_Framing    : std_logic;
    signal Stat_ImageOpen : std_logic;

    signal Side      : std_logic_vector(YW_c + XW_c - 1 downto 0);
    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;

    -- Cycles with Err_Framing high
    signal Framing  : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    i_dut : entity work.isp_frame_sync
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => PixelBits_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => In_Valid,
            In_Ready       => In_Ready,
            In_Data        => In_Data,
            In_Last        => In_Last,
            In_User        => In_User,
            Out_Valid      => Out_Valid,
            Out_Ready      => Out_Ready,
            Out_Data       => Out_Data,
            Out_Last       => Out_Last,
            Out_User       => Out_User,
            Out_PosX       => Out_PosX,
            Out_PosY       => Out_PosY,
            Err_Framing    => Err_Framing,
            Stat_ImageOpen => Stat_ImageOpen
        );

    i_source : entity work.isp_tb_source
        generic map (
            Width_g      => PixelBits_g,
            StimFile_g   => StimFile_g,
            GapPct_g     => GapPct_g,
            Seed_g       => Seed_g,
            ProbeWidth_g => 1
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            M_Valid   => In_Valid,
            M_Ready   => In_Ready,
            M_Data    => In_Data,
            M_Last    => In_Last,
            M_User    => In_User,
            SinkCount => SinkCount,
            Probe(0)  => Stat_ImageOpen,
            RstReq    => RstReq,
            Hold      => Hold,
            Marker    => Marker,
            Done      => SrcDone
        );

    Side <= Out_PosY & Out_PosX;

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => PixelBits_g,
            SideWidth_g => YW_c + XW_c,
            ExpFile_g   => ExpFile_g,
            StallPct_g  => StallPct_g,
            Seed_g      => Seed_g + 1,
            OutWidth_g  => ImageWidth_g,
            OutHeight_g => ImageHeight_g
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            S_Valid => Out_Valid,
            S_Ready => Out_Ready,
            S_Data  => Out_Data,
            S_Last  => Out_Last,
            S_User  => Out_User,
            S_Side  => Side,
            Hold    => Hold,
            Count   => SinkCount,
            Done    => SinkDone
        );

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        -- Every test runs its stimulus file against the model; test_rate adds the timing checks
        while test_suite loop
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_images") or run("test_short_images") or run("test_excess_pixels") or
                  run("test_end_flags") or run("test_reset") or run("test_status") or
                  run("test_random_streams") then
                RateTest <= false;
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            wait until SrcDone and SinkDone;

            for i in 1 to Drain_c loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Framing, ExpFraming_g, ERROR, "number of Err_Framing pulses");
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Err_Framing pulses; metavalues of the control outputs; outputs after a reset
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
    begin
        if rising_edge(Clk) then
            if Started_v then
                if is_x(In_Ready) or is_x(Out_Valid) or is_x(Err_Framing) or is_x(Stat_ImageOpen) then
                    error("metavalue on a control output: In_Ready " & std_logic'image(In_Ready) &
                          ", Out_Valid " & std_logic'image(Out_Valid) & ", Err_Framing " &
                          std_logic'image(Err_Framing) & ", Stat_ImageOpen " & std_logic'image(Stat_ImageOpen));
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Framing /= '0' or Stat_ImageOpen /= '0') then
                    error("after a reset: Out_Valid, Err_Framing and Stat_ImageOpen must be 0");
                end if;
                if Err_Framing = '1' then
                    Framing <= Framing + 1;
                end if;
            end if;
            if RstPrev_v = '1' and Rst = '0' then
                Started_v := true;
            end if;
            RstPrev_v := Rst;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Timing of test_rate (FSY-PF-01 to FSY-PF-04)
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        variable Cycle_v    : natural := 0;
        variable PrevMark_v : natural := 0;
        -- Phase 1: input and output beats, the cycles of the first and the last of each
        variable InN_v      : natural := 0;
        variable OutN_v     : natural := 0;
        variable InFirst_v  : natural := 0;
        variable InLast_v   : natural := 0;
        variable OutFirst_v : natural := 0;
        variable OutLast_v  : natural := 0;
        -- Phase 2: cycle of the accepted image start, measurement pending
        variable SofCyc_v   : natural := 0;
        variable SofSeen_v  : boolean := false;
        variable Pending_v  : boolean := false;
        variable M_v        : natural := 0;
    begin
        if rising_edge(Clk) and RateTest then
            Cycle_v := Cycle_v + 1;

            -- End of phase 1: evaluate
            if PrevMark_v = 1 and Marker /= 1 then
                check_value(OutN_v, InN_v, ERROR, "test_rate phase 1: output beats equal input beats");
                check_value(InLast_v - InFirst_v + 1, InN_v, ERROR,
                            "test_rate phase 1: one input beat per cycle (FSY-PF-01)");
                check_value(OutLast_v - OutFirst_v + 1, OutN_v, ERROR,
                            "test_rate phase 1: one output beat per cycle (FSY-PF-01)");
                check_value(OutFirst_v - InFirst_v, 2, ERROR, "test_rate phase 1: latency (FSY-PF-02)");
                log(ID_SEQUENCER, "test_rate phase 1: " & integer'image(InN_v) & " beats, latency " &
                    integer'image(OutFirst_v - InFirst_v) & " cycles");
            end if;

            if Marker = 1 then
                if In_Valid = '1' and In_Ready = '1' then
                    if InN_v = 0 then
                        InFirst_v := Cycle_v;
                    end if;
                    InN_v    := InN_v + 1;
                    InLast_v := Cycle_v;
                end if;
                if Out_Valid = '1' and Out_Ready = '1' then
                    if OutN_v = 0 then
                        OutFirst_v := Cycle_v;
                    end if;
                    OutN_v    := OutN_v + 1;
                    OutLast_v := Cycle_v;
                end if;
            end if;

            -- Phase 2: marker 1000 + m before the image start that completes an image with m missing pixels
            if Marker >= 1000 and Marker /= PrevMark_v then
                M_v       := Marker - 1000;
                SofSeen_v := false;
                Pending_v := true;
            end if;
            if Pending_v then
                if not SofSeen_v and In_Valid = '1' and In_Ready = '1' then
                    SofSeen_v := true;
                    SofCyc_v  := Cycle_v;
                end if;
                if SofSeen_v and Out_Valid = '1' and Out_Ready = '1' and
                   unsigned(Out_PosX) = 0 and unsigned(Out_PosY) = 0 then
                    if Cycle_v - SofCyc_v > M_v + 4 then
                        error("test_rate: first pixel after " & integer'image(M_v) & " missing pixels at " &
                              integer'image(Cycle_v - SofCyc_v) & " cycles, at most " & integer'image(M_v + 4) &
                              " (FSY-PF-03)");
                    else
                        log(ID_SEQUENCER, "test_rate: first pixel after " & integer'image(M_v) &
                            " missing pixels at " & integer'image(Cycle_v - SofCyc_v) & " cycles");
                    end if;
                    Pending_v := false;
                end if;
            end if;

            -- Phase 3: pixels without an image start are taken in every cycle, output held (FSY-PF-04)
            if Marker = 4 and In_Valid = '1' and In_Ready = '0' then
                error("test_rate: a discarded pixel waits while the output is held (FSY-PF-04)");
            end if;

            PrevMark_v := Marker;
        end if;
    end process;

end architecture;
