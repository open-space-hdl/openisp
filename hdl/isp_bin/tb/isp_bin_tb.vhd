---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_bin: the shared source sends the pixel stream of the test, the shared sink
-- compares every output pixel with the expected file of the reference model and checks the output
-- contract (Wo x Ho), and the injection script drives the error injection into the line buffers of
-- the vertical filter. The testbench counts the pulses of the status outputs, monitors the control
-- outputs for metavalues and their state after every reset, and checks the timing of test_rate.
--
-- * test_rate: hold cycles of the input, image period, latency of every pixel from the timing file
--   (marker 1) and the fall of Stat_ImageOpen after the last pixel of an image (verification plan,
--   section 5)
--
-- Documentation: hdl/isp_bin/docs/verification_plan.md

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
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_bin_tb is
    generic (
        runner_cfg    : string;
        ImageWidth_g  : positive := 13;
        ImageHeight_g : positive := 9;
        PixelBits_g   : positive := 12;
        BinX_g        : positive := 2;
        BinY_g        : positive := 2;
        BorderMode_g  : string   := "valid";
        EccPipeline_g : natural  := 1;
        Resource_g    : string   := "AUTO";
        -- Output image (Wo x Ho), from the model
        OutWidth_g    : positive := 6;
        OutHeight_g   : positive := 4;
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

architecture sim of isp_bin_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant Valid_c     : boolean  := BorderMode_g = "valid";
    constant Lx_c        : natural  := log2ceil(BinX_g);
    constant Ly_c        : natural  := log2ceil(BinY_g);
    constant Q_c         : positive := PixelBits_g + log2ceil(BinX_g * BinY_g);
    constant FlipW_c     : positive := maximum(BinY_g - 1, 1) * eccCodewordWidth(PixelBits_g + Lx_c);
    -- The parts present (architecture, section 2)
    constant HorOn_c     : boolean := BinX_g > 1;
    constant VerOn_c     : boolean := BinY_g > 1;

    -- Width of the narrowed image (Wo)
    function narrowWidth return positive is
    begin
        if Valid_c then
            return ImageWidth_g / BinX_g;
        end if;
        return (ImageWidth_g + BinX_g - 1) / BinX_g;
    end function;

    constant Wo_c : positive := narrowWidth;

    -- Design values of test_rate (verification plan, section 5). Holds of the input per line: the BinX_g - 1
    -- virtual columns of the horizontal filter (none in the border mode valid)
    function holdMax return natural is
    begin
        if Valid_c then
            return 0;
        end if;
        return BinX_g - 1;
    end function;

    -- N: the virtual pixels of the vertical filter after every image, during which its input waits
    function vpix return natural is
    begin
        if Valid_c or not VerOn_c then
            return 0;
        end if;
        return (BinY_g - 1) * Wo_c;
    end function;

    -- d: the wait of the input of an image that follows an image (BIN-PF-01); without the horizontal filter the
    -- input waits for all N virtual pixels (the window, WIN-PF-01)
    function waitMax return natural is
    begin
        if not HorOn_c then
            return vpix;
        end if;
        return maximum(0, vpix + 2 - 2 * BinX_g);
    end function;

    -- Bins in the kernel of the horizontal filter when it freezes: ceil(S / BinX_g), S = 3 + log2ceil(BinX_g)
    constant KerBins_c : positive := (3 + Lx_c + BinX_g - 1) / BinX_g;

    -- A: the input cycles that the buffers between the window of the vertical filter and the input take while
    -- the vertical filter waits: the frame sync of the vertical filter (3 bins: its output register and the two
    -- entries of its input stage), the kernel of the horizontal filter (KerBins_c bins), its window register
    -- (1 bin), BinX_g - 1 events before the next window and its frame sync (3 pixels)
    function absorb return natural is
    begin
        if not (HorOn_c and VerOn_c) then
            return 0;
        end if;
        return BinX_g * (4 + KerBins_c) + BinX_g - 1 + 3;
    end function;

    -- The exact wait when the buffers fill within line 0 of the image (verification plan, section 5): the first
    -- pixel held is p = BinX_g x (4 + KerBins_c) + 3, the input is released 2 cycles after the first pixel event of
    -- the vertical filter (the registered ready of both input stages); -1 where the range applies
    function waitExact return integer is
        constant P_c : natural := BinX_g * (4 + KerBins_c) + 3;
        constant E_c : integer := vpix + 8 + Lx_c - BinX_g * (5 + KerBins_c);
    begin
        if HorOn_c and VerOn_c and vpix > 0 and P_c < ImageWidth_g and E_c > 0 then
            return E_c;
        elsif not HorOn_c then
            return vpix;
        end if;
        return -1;
    end function;

    -- Latency from the acceptance of the last pixel of a bin to the output: per filter 6 to 8 + log2ceil of its
    -- factor (isp_filter2d, FLT-PF-02), the frame sync alone 2
    function latMin return positive is
    begin
        if HorOn_c and VerOn_c then
            return 12 + Lx_c + Ly_c;
        elsif HorOn_c then
            return 6 + Lx_c;
        elsif VerOn_c then
            return 6 + Ly_c;
        end if;
        return 2;
    end function;

    function latMax return positive is
    begin
        if HorOn_c and VerOn_c then
            return 16 + Lx_c + Ly_c;
        elsif HorOn_c then
            return 8 + Lx_c;
        elsif VerOn_c then
            return 8 + Ly_c;
        end if;
        return 2;
    end function;

    -- Fall of Stat_ImageOpen after the acceptance of the last pixel of an image: the frame sync of the input one
    -- cycle later; with both filters the vertical one, when the last bin enters it (7 + log2ceil(BinX_g))
    function fallDelay return positive is
    begin
        if HorOn_c and VerOn_c then
            return 7 + Lx_c;
        end if;
        return 1;
    end function;

    constant HoldMax_c  : natural  := holdMax;
    constant Wait_c     : natural  := waitMax;
    constant Exact_c    : integer  := waitExact;
    constant WaitLo_c   : natural  := choose(Exact_c >= 0, maximum(Exact_c, 0), maximum(0, Wait_c - absorb));
    constant WaitHi_c   : natural  := choose(Exact_c >= 0, maximum(Exact_c, 0), Wait_c);
    constant Base_c     : positive := ImageHeight_g * (ImageWidth_g + HoldMax_c);
    constant PerMin_c   : positive := Base_c + WaitLo_c;
    constant PerMax_c   : positive := Base_c + WaitHi_c;
    constant LatMin_c   : positive := latMin;
    constant LatMax_c   : positive := latMax;
    constant Fall_c     : positive := fallDelay;
    -- Drain time of the test end: the virtual pixels of both filters, the latencies and 21
    -- (docs/testbench.md, section 6)
    constant Drain_c    : positive := vpix + BinX_g + 2 * LatMax_c + 21;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c : positive := 4096;

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
    signal Out_Data       : std_logic_vector(Q_c - 1 downto 0);
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

    -- Cycles with the status pulses high
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

    -----------------------------------------------------------------------------------------------
    -- Device under test
    -----------------------------------------------------------------------------------------------
    i_dut : entity work.isp_bin
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => PixelBits_g,
            BinX_g        => BinX_g,
            BinY_g        => BinY_g,
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
            Width_g     => Q_c,
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
            elsif run("test_static") or run("test_input_stream") or run("test_ecc") or run("test_reset") then
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
    -- Pulses; metavalues of the control outputs and of the output pixels; outputs after a reset
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
                    error("metavalue in an output pixel");
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Framing /= '0' or Stat_ImageOpen /= '0' or
                                        Stat_EccSec /= '0' or Stat_EccDed /= '0') then
                    error("after a reset: Out_Valid and the status outputs must be 0");
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
    -- Timing of test_rate (BIN-PF-01, BIN-PF-02), images back to back from the reset on
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        type Cycles_t is array (0 to AccDepth_c - 1) of natural;

        variable Acc_v      : Cycles_t;
        variable InN_v      : natural   := 0;
        variable OutN_v     : natural   := 0;
        variable Opened_v   : boolean   := false;
        variable L_v        : line;
        variable W_v        : string(1 to WordMax_c);
        variable Len_v      : natural;
        variable Src_v      : integer;
        variable Lat_v      : natural;
        variable LatLo_v    : natural   := natural'high;
        variable LatHi_v    : natural   := 0;
        variable Held_v     : natural   := 0;
        variable HeldMax_v  : natural   := 0;
        variable WaitImg_v  : natural   := 0;
        variable Long_v     : natural   := 0;
        variable ImgStart_v : integer   := -1;
        variable Period_v   : integer   := -1;
        variable Periods_v  : natural   := 0;
        variable PixInImg_v : natural;
        variable LastPix_v  : integer   := -1;
        variable OpenPrev_v : std_logic := '0';
        variable Falls_v    : natural   := 0;

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

            -- Fall of Stat_ImageOpen: the value sampled here is the one after the edge before, so the fall took
            -- place at the edge Cycle - 1
            if Marker >= 1 and OpenPrev_v = '1' and Stat_ImageOpen = '0' and LastPix_v >= 0 then
                check_value(Cycle - 1 - LastPix_v, Fall_c, ERROR,
                            "test_rate: cycles from the acceptance of the last pixel of an image to the fall of " &
                            "Stat_ImageOpen");
                Falls_v := Falls_v + 1;
            end if;
            OpenPrev_v := Stat_ImageOpen;

            if In_Valid = '1' and In_Ready = '1' then
                Acc_v(InN_v mod AccDepth_c) := Cycle;
                PixInImg_v                  := InN_v mod (ImageWidth_g * ImageHeight_g);
                if PixInImg_v = ImageWidth_g * ImageHeight_g - 1 then
                    LastPix_v := Cycle;
                end if;
                if Marker = 1 and PixInImg_v mod ImageWidth_g = 0 then
                    if PixInImg_v = 0 then
                        -- Image start: the interval from the image start before (BIN-PF-02). The first interval
                        -- after an idle module is at most the largest period; every further one is the same and
                        -- lies in the range of the design
                        if ImgStart_v >= 0 then
                            if Periods_v = 0 then
                                check_value(Cycle - ImgStart_v <= PerMax_c, ERROR,
                                            "test_rate: first interval between two image starts " &
                                            integer'image(Cycle - ImgStart_v) & ", at most " &
                                            integer'image(PerMax_c) & " (BIN-PF-02)");
                            elsif Period_v < 0 then
                                Period_v := Cycle - ImgStart_v;
                                check_value(Period_v >= PerMin_c and Period_v <= PerMax_c, ERROR,
                                            "test_rate: interval between two image starts " &
                                            integer'image(Period_v) & ", design " & integer'image(PerMin_c) &
                                            " to " & integer'image(PerMax_c) & " (BIN-PF-02)");
                            else
                                check_value(Cycle - ImgStart_v, Period_v, ERROR,
                                            "test_rate: interval between two image starts, the same as before " &
                                            "(BIN-PF-02)");
                            end if;
                            Periods_v := Periods_v + 1;
                        end if;
                        ImgStart_v := Cycle;
                        Long_v     := 0;
                    else
                        -- First pixel of a line: the hold cycles since the first pixel of the line before
                        -- (BIN-PF-01); in an image that follows an image one line interval may also hold the wait
                        -- for the virtual lines of the vertical filter
                        if Held_v > HoldMax_c then
                            Long_v    := Long_v + 1;
                            check_value(InN_v >= ImageWidth_g * ImageHeight_g and Long_v = 1 and
                                        Held_v <= HoldMax_c + WaitHi_c, ERROR,
                                        "test_rate: " & integer'image(Held_v) & " hold cycles between the first " &
                                        "pixels of two lines, at most " & integer'image(HoldMax_c) & ", and " &
                                        integer'image(HoldMax_c + WaitHi_c) & " once in an image that follows an " &
                                        "image (BIN-PF-01)");
                            WaitImg_v := Held_v - HoldMax_c;
                        elsif Held_v > HeldMax_v then
                            HeldMax_v := Held_v;
                        end if;
                    end if;
                    Held_v := 0;
                end if;
                InN_v := InN_v + 1;
            end if;

            -- Every output pixel: the input beat that completes its bin, from the timing file of the model
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    Lat_v := Cycle - Acc_v(Src_v mod AccDepth_c);
                    check_value(Lat_v >= LatMin_c and Lat_v <= LatMax_c, ERROR,
                                "test_rate: latency " & integer'image(Lat_v) & " of output pixel " &
                                integer'image(OutN_v) & ", design " & integer'image(LatMin_c) & " to " &
                                integer'image(LatMax_c));
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
                check_value(Falls_v > 0, ERROR, "test_rate: no fall of Stat_ImageOpen measured");
                log(ID_SEQUENCER, "test_rate: latency " & integer'image(LatLo_v) & " to " & integer'image(LatHi_v) &
                    " cycles, at most " & integer'image(HeldMax_v) & " hold cycles per line, a wait of " &
                    integer'image(WaitImg_v) & " cycles for the virtual lines (design " &
                    integer'image(WaitLo_c) & " to " & integer'image(WaitHi_c) & "), " &
                    integer'image(Periods_v) & " image intervals, period " & integer'image(Period_v) &
                    " (design " & integer'image(PerMin_c) & " to " & integer'image(PerMax_c) & "), " &
                    integer'image(Falls_v) & " falls of Stat_ImageOpen " & integer'image(Fall_c) &
                    " cycles after the last pixel");
                Periods_v := 0;
            end if;
        end if;
    end process;

end architecture;
