---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_window: the shared source sends the stimulus file of the test, the shared sink
-- compares every window with the expected file of the reference model and checks the output
-- contract (Wo x Ho), and the injection script drives the error injection of the line buffers. The
-- testbench counts the Err_Framing, Stat_EccSec and Stat_EccDed pulses, monitors the control
-- outputs for metavalues and their state after every reset, and checks the timing of test_rate.
--
-- * test_rate (marker 1): latency of every window from the timing file, hold cycles of the input
--   between the first pixels of two lines of an image, interval between two image starts
--
-- Documentation: hdl/isp_window/docs/verification_plan.md

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

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_window_tb is
    generic (
        runner_cfg    : string;
        ImageWidth_g  : positive := 10;
        ImageHeight_g : positive := 7;
        PixelBits_g   : positive := 12;
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        AnchorX_g     : natural  := 1;
        AnchorY_g     : natural  := 1;
        StrideX_g     : positive := 1;
        StrideY_g     : positive := 1;
        BorderMode_g  : string   := "replicate";
        EccPipeline_g : natural  := 1;
        Resource_g    : string   := "AUTO";
        -- Output image (Wo x Ho), from the model
        OutWidth_g    : positive := 10;
        OutHeight_g   : positive := 7;
        StimFile_g    : string;
        ExpFile_g     : string;
        InjFile_g     : string;
        TimFile_g     : string;
        GapPct_g      : natural  := 0;
        StallPct_g    : natural  := 0;
        Seed_g        : positive := 1;
        -- Numbers of Err_Framing, Stat_EccSec and Stat_EccDed pulses of the model
        ExpFraming_g  : natural  := 0;
        ExpSec_g      : natural  := 0;
        ExpDed_g      : natural  := 0;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g  : positive := 1000
    );
end entity;

architecture sim of isp_window_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant Valid_c     : boolean  := BorderMode_g = "valid";
    constant Rr_c        : natural  := WinX_g - 1 - AnchorX_g;
    constant Rb_c        : natural  := WinY_g - 1 - AnchorY_g;
    constant DataW_c     : positive := WinX_g * WinY_g * PixelBits_g;
    constant FlipW_c     : positive := maximum(WinY_g - 1, 1) * eccCodewordWidth(PixelBits_g);
    -- Design values of the timing (verification plan, section 5)
    constant LatMin_c    : positive := 3;
    constant LatMax_c    : positive := 5;

    function holdMax return natural is
    begin
        if Valid_c then
            return 0;
        end if;
        return Rr_c;
    end function;

    function period return positive is
    begin
        if Valid_c then
            return ImageHeight_g * ImageWidth_g;
        end if;
        return (ImageHeight_g + Rb_c) * (ImageWidth_g + Rr_c);
    end function;

    constant HoldMax_c : natural := holdMax;

    -- Between the first two lines of an image that follows an image: also the virtual lines of the image before
    function holdFirst return natural is
    begin
        if Valid_c then
            return 0;
        end if;
        return Rb_c * (ImageWidth_g + Rr_c) + Rr_c;
    end function;

    constant HoldFirst_c : natural  := holdFirst;
    constant Period_c    : positive := period;
    -- Drain time of the test end: the windows of the borders follow the last pixel, plus the latency and 21
    -- (docs/testbench.md, section 6)
    constant Drain_c     : positive := Rb_c * (ImageWidth_g + Rr_c) + Rr_c + LatMax_c + 21;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c  : positive := 4096;

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
    signal Out_Data       : std_logic_vector(DataW_c - 1 downto 0);
    signal Out_Last       : std_logic;
    signal Out_User       : std_logic_vector(1 downto 0);
    signal Err_Framing    : std_logic;
    signal Stat_ImageOpen : std_logic;
    signal Stat_EccSec    : std_logic;
    signal Stat_EccDed    : std_logic;
    signal ErrInj_BitFlip : std_logic_vector(FlipW_c - 1 downto 0);
    signal ErrInj_Valid   : std_logic;

    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;
    signal Ack       : natural;

    -- Cycles with Err_Framing, Stat_EccSec and Stat_EccDed high
    signal Framing  : natural := 0;
    signal Sec      : natural := 0;
    signal Ded      : natural := 0;
    signal Cycle    : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    i_dut : entity work.isp_window
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => PixelBits_g,
            WinX_g        => WinX_g,
            WinY_g        => WinY_g,
            AnchorX_g     => AnchorX_g,
            AnchorY_g     => AnchorY_g,
            StrideX_g     => StrideX_g,
            StrideY_g     => StrideY_g,
            BorderMode_g  => BorderMode_g,
            EccPipeline_g => EccPipeline_g,
            Resource_g    => Resource_g
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
            Err_Framing    => Err_Framing,
            Stat_ImageOpen => Stat_ImageOpen,
            Stat_EccSec    => Stat_EccSec,
            Stat_EccDed    => Stat_EccDed,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid
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
            Ack       => Ack,
            Done      => SrcDone
        );

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => DataW_c,
            SideWidth_g => 1,
            ExpFile_g   => ExpFile_g,
            StallPct_g  => StallPct_g,
            Seed_g      => Seed_g + 1,
            OutWidth_g  => OutWidth_g,
            OutHeight_g => OutHeight_g
        )
        port map (
            Clk     => Clk,
            Rst     => Rst,
            S_Valid => Out_Valid,
            S_Ready => Out_Ready,
            S_Data  => Out_Data,
            S_Last  => Out_Last,
            S_User  => Out_User,
            S_Side  => "0",
            Hold    => Hold,
            Count   => SinkCount,
            Done    => SinkDone
        );

    i_inject : entity work.isp_tb_inject
        generic map (
            InjFile_g   => InjFile_g,
            FlipWidth_g => FlipW_c
        )
        port map (
            Clk            => Clk,
            Marker         => Marker,
            Ack            => Ack,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid,
            Scrub_Enable   => open
        );

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        -- Every test runs its stimulus and injection files against the model; test_rate adds the timing checks
        while test_suite loop
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_static") or run("test_input_stream") or run("test_handshake") or run("test_ecc") or
                  run("test_reset") then
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
            check_value(Sec, ExpSec_g, ERROR, "number of Stat_EccSec pulses");
            check_value(Ded, ExpDed_g, ERROR, "number of Stat_EccDed pulses");
        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Pulses; metavalues of the control outputs and of the windows; outputs after a reset
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
    begin
        if rising_edge(Clk) then
            Cycle <= Cycle + 1;
            if Started_v then
                if is_x(In_Ready) or is_x(Out_Valid) or is_x(Err_Framing) or is_x(Stat_ImageOpen) or
                   is_x(Stat_EccSec) or is_x(Stat_EccDed) then
                    error("metavalue on a control output: In_Ready " & std_logic'image(In_Ready) &
                          ", Out_Valid " & std_logic'image(Out_Valid) & ", Err_Framing " &
                          std_logic'image(Err_Framing) & ", Stat_ImageOpen " & std_logic'image(Stat_ImageOpen) &
                          ", Stat_EccSec " & std_logic'image(Stat_EccSec) & ", Stat_EccDed " &
                          std_logic'image(Stat_EccDed));
                end if;
                if Out_Valid = '1' and is_x(Out_Data) then
                    error("metavalue in an output window (WIN-FT-04)");
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Framing /= '0' or Stat_ImageOpen /= '0' or
                                        Stat_EccSec /= '0' or Stat_EccDed /= '0') then
                    error("after a reset: Out_Valid, Err_Framing, Stat_ImageOpen and the ECC pulses must be 0");
                end if;
                if Err_Framing = '1' then
                    Framing <= Framing + 1;
                end if;
                if Stat_EccSec = '1' then
                    Sec <= Sec + 1;
                end if;
                if Stat_EccDed = '1' then
                    Ded <= Ded + 1;
                end if;
            end if;
            if RstPrev_v = '1' and Rst = '0' then
                Started_v := true;
            end if;
            RstPrev_v := Rst;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Timing of test_rate (WIN-PF-01 to WIN-PF-03), images back to back from the reset on
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        type Cycles_t is array (0 to AccDepth_c - 1) of natural;

        variable Acc_v      : Cycles_t;
        variable InN_v      : natural := 0;
        variable OutN_v     : natural := 0;
        variable Opened_v   : boolean := false;
        variable L_v        : line;
        variable W_v        : string(1 to WordMax_c);
        variable Len_v      : natural;
        variable Src_v      : integer;
        variable Lat_v      : natural;
        variable LatLo_v    : natural := natural'high;
        variable LatHi_v    : natural := 0;
        variable Held_v     : natural := 0;
        variable HeldMax_v  : natural := 0;
        variable ImgStart_v : integer := -1;
        variable Line_v     : natural := 0;
        variable Periods_v  : natural := 0;
        variable PixInImg_v : natural;

        file F_v : text;
    begin
        if rising_edge(Clk) and RateTest then
            if not Opened_v then
                file_open(F_v, TimFile_g, read_mode);
                Opened_v := true;
            end if;

            if Marker = 1 and In_Valid = '1' and In_Ready = '0' then
                Held_v := Held_v + 1;
            end if;

            if In_Valid = '1' and In_Ready = '1' then
                Acc_v(InN_v mod AccDepth_c) := Cycle;
                PixInImg_v                  := InN_v mod (ImageWidth_g * ImageHeight_g);
                if Marker = 1 and PixInImg_v mod ImageWidth_g = 0 then
                    if PixInImg_v = 0 then
                        -- Image start: the interval from the image start before (WIN-PF-02). The input stage takes
                        -- the image start after the last pixel of the image before, during its virtual lines; so the
                        -- first interval after an idle module is shorter, and every further one has the period
                        if ImgStart_v >= 0 then
                            if Periods_v = 0 then
                                check_value(Cycle - ImgStart_v <= Period_c, ERROR,
                                            "test_rate: first interval between two image starts " &
                                            integer'image(Cycle - ImgStart_v) & ", at most " &
                                            integer'image(Period_c) & " (WIN-PF-02)");
                            else
                                check_value(Cycle - ImgStart_v, Period_c, ERROR,
                                            "test_rate: interval between two image starts (WIN-PF-02)");
                            end if;
                            Periods_v := Periods_v + 1;
                        end if;
                        ImgStart_v := Cycle;
                    else
                        -- First pixel of a line of the image: the hold cycles since the first pixel of the line
                        -- before (WIN-PF-01); line 1 of an image after an image also waits for its virtual lines
                        Line_v := PixInImg_v / ImageWidth_g;
                        if Line_v = 1 and InN_v >= ImageWidth_g * ImageHeight_g then
                            check_value(Held_v <= HoldFirst_c, ERROR,
                                        "test_rate: " & integer'image(Held_v) & " hold cycles between the first " &
                                        "pixels of the first two lines, at most " & integer'image(HoldFirst_c) &
                                        " (WIN-PF-01)");
                        else
                            if Held_v > HeldMax_v then
                                HeldMax_v := Held_v;
                            end if;
                            check_value(Held_v <= HoldMax_c, ERROR,
                                        "test_rate: " & integer'image(Held_v) & " hold cycles between the first " &
                                        "pixels of two lines, at most " & integer'image(HoldMax_c) & " (WIN-PF-01)");
                        end if;
                    end if;
                    Held_v := 0;
                end if;
                InN_v := InN_v + 1;
            end if;

            -- Every window: the input beat that completes it, from the timing file of the model (WIN-PF-03)
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    Lat_v := Cycle - Acc_v(Src_v mod AccDepth_c);
                    check_value(Lat_v >= LatMin_c and Lat_v <= LatMax_c, ERROR,
                                "test_rate: latency " & integer'image(Lat_v) & " of window " & integer'image(OutN_v) &
                                ", design 3 to 5 (WIN-PF-03)");
                    if Lat_v < LatLo_v then
                        LatLo_v := Lat_v;
                    end if;
                    if Lat_v > LatHi_v then
                        LatHi_v := Lat_v;
                    end if;
                end if;
                OutN_v := OutN_v + 1;
            end if;

            if Marker = 2 and Periods_v > 0 then
                log(ID_SEQUENCER, "test_rate: latency " & integer'image(LatLo_v) & " to " & integer'image(LatHi_v) &
                    " cycles, at most " & integer'image(HeldMax_v) & " hold cycles per line, " &
                    integer'image(Periods_v) & " image periods of " & integer'image(Period_c) & " cycles");
                Periods_v := 0;
            end if;
        end if;
    end process;

end architecture;
