---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of isp_filter2d: the shared source sends the pixel stream of the test, the shared sink
-- compares every output pixel with the expected file of the reference model and checks the output
-- contract (Wo x Ho), the register script of the test runs on the AXI4-Lite slave of the filter and
-- the injection script drives the error injection into the line buffers. The coefficient sets are
-- string generics (ispIntList). The testbench counts the pulses of the status outputs, monitors the
-- control outputs for metavalues and their state after every reset, and checks the timing of
-- test_rate. With Separable_g, two filters run in series (WinX_g x WinY_g, then Win2X_g x Win2Y_g),
-- the first at full precision; its status pulses and those of the second are counted together.
--
-- * test_rate: hold cycles of the input and image period of isp_window, latency of every pixel from
--   the timing file (marker 1)
--
-- Documentation: hdl/isp_filter2d/docs/verification_plan.md

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

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

library work;
    use work.isp_pkg.all;
    use work.isp_tb_pkg.all;
    use work.isp_tb_axilite_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_filter2d_tb is
    generic (
        runner_cfg    : string;
        ImageWidth_g  : positive := 12;
        ImageHeight_g : positive := 8;
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
        CoefBits_g    : positive := 16;
        -- Coefficients of the generic: decimal values separated by commas, element 0 first
        CoefStr_g     : string   := "0,0,0,0,1,0,0,0,0";
        RuntimeCoef_g : boolean  := false;
        OutBits_g     : natural  := 0;
        -- Two filters in series: the second has the window Win2X_g x Win2Y_g (anchor in the middle, stride 1,
        -- the border mode of the first) and the coefficients Coef2Str_g; the first runs at full precision
        Separable_g   : boolean  := false;
        Win2X_g       : positive := 1;
        Win2Y_g       : positive := 1;
        Coef2Str_g    : string   := "1";
        -- Output image (Wo x Ho), from the model
        OutWidth_g    : positive := 12;
        OutHeight_g   : positive := 8;
        StimFile_g    : string;
        ExpFile_g     : string;
        RegsFile_g    : string;
        InjFile_g     : string;
        TimFile_g     : string;
        GapPct_g      : natural  := 0;
        StallPct_g    : natural  := 0;
        Seed_g        : positive := 1;
        -- Numbers of Err_Framing, Stat_EccSec, Stat_EccDed and Err_Config pulses of the model
        ExpFraming_g  : natural  := 0;
        ExpSec_g      : natural  := 0;
        ExpDed_g      : natural  := 0;
        ExpConfig_g   : natural  := 0;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g  : positive := 1000
    );
end entity;

architecture sim of isp_filter2d_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant Valid_c     : boolean  := BorderMode_g = "valid";
    constant T_c         : positive := WinX_g * WinY_g;
    constant Rr_c        : natural  := WinX_g - 1 - AnchorX_g;
    constant Rb_c        : natural  := WinY_g - 1 - AnchorY_g;
    constant FlipW_c     : positive := maximum(WinY_g - 1, 1) * eccCodewordWidth(PixelBits_g);
    -- Output width of the first filter: full precision when a second one follows
    constant B1_c        : positive := ispConvOutBits(PixelBits_g, CoefBits_g, T_c, choose(Separable_g, 0, OutBits_g));
    constant B2_c        : positive := ispConvOutBits(B1_c, CoefBits_g, Win2X_g * Win2Y_g, OutBits_g);
    constant B_c         : positive := choose(Separable_g, B2_c, B1_c);
    -- Design values of the timing (verification plan, section 5): window 3 to 5, kernel 3 + log2ceil(T)
    constant LatMin_c    : positive := 6 + log2ceil(T_c);
    constant LatMax_c    : positive := 8 + log2ceil(T_c);

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

    -- Between the first two lines of an image that follows an image: also the virtual lines of the image before
    function holdFirst return natural is
    begin
        if Valid_c then
            return 0;
        end if;
        return Rb_c * (ImageWidth_g + Rr_c) + Rr_c;
    end function;

    -- Output size of a window generator along one axis (specification of isp_window, section 1.1)
    function winOut (n : positive; win : positive; stride : positive) return positive is
    begin
        if Valid_c then
            return (n - win) / stride + 1;
        end if;
        return (n + stride - 1) / stride;
    end function;

    constant HoldMax_c   : natural  := holdMax;
    constant HoldFirst_c : natural  := holdFirst;
    constant Period_c    : positive := period;
    -- Drain time of the test end: the windows of the borders follow the last pixel (of both filters in series),
    -- plus the latencies and 21 (docs/testbench.md, section 6)
    constant Drain_c     : positive := 2 * (Rb_c * (ImageWidth_g + Rr_c) + Rr_c + LatMax_c) +
                                       Win2Y_g * (ImageWidth_g + Win2X_g) + 21;
    constant AdrStatus_c : natural  := 16#00C#;
    -- Acceptance cycles of the input beats kept for the latency check
    constant AccDepth_c  : positive := 4096;

    -- Number of filters with the pulse high in this cycle
    function count (v : std_logic_vector) return natural is
        variable N_v : natural := 0;
    begin

        for i in v'range loop
            if v(i) = '1' then
                N_v := N_v + 1;
            end if;
        end loop;

        return N_v;
    end function;

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
    signal Out_Data       : std_logic_vector(B_c - 1 downto 0);
    signal Out_Last       : std_logic;
    signal Out_User       : std_logic_vector(1 downto 0);
    signal ErrInj_BitFlip : std_logic_vector(FlipW_c - 1 downto 0);
    signal ErrInj_Valid   : std_logic;

    -- Status outputs of the filter (index 0) and of the second filter of Separable_g (index 1, else 0)
    signal Err_Framing    : std_logic_vector(0 to 1);
    signal Stat_ImageOpen : std_logic_vector(0 to 1);
    signal Stat_EccSec    : std_logic_vector(0 to 1);
    signal Stat_EccDed    : std_logic_vector(0 to 1);
    signal Err_Config     : std_logic_vector(0 to 1);

    signal Axi : t_axilite_if(
                               write_address_channel(
                                                        awaddr(11 downto 0)),
                               write_data_channel(
                                                     wdata(31 downto 0),
                                                     wstrb(3 downto 0)),
                               read_address_channel(
                                                       araddr(11 downto 0)),
                               read_data_channel(
                                                    rdata(31 downto 0))) := init_axilite_if_signals(12, 32);

    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;
    -- Acknowledges of the register script and of the injection script; the source waits for the larger
    signal AckRegs   : natural := 0;
    signal AckInj    : natural;
    signal Ack       : natural;

    -- Cycles with the status pulses high, summed over the filters
    signal Framing  : natural := 0;
    signal Sec      : natural := 0;
    signal Ded      : natural := 0;
    signal Config   : natural := 0;
    signal Cycle    : natural := 0;
    -- Timing checks of test_rate are active
    signal RateTest : boolean := false;

begin

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;
    Ack <= maximum(AckRegs, AckInj);

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    -----------------------------------------------------------------------------------------------
    -- One filter
    -----------------------------------------------------------------------------------------------
    g_single : if not Separable_g generate

        i_dut : entity work.isp_filter2d
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
                Resource_g    => Resource_g,
                CoefBits_g    => CoefBits_g,
                Coef_g        => ispIntList(CoefStr_g),
                RuntimeCoef_g => RuntimeCoef_g,
                OutBits_g     => OutBits_g
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => In_Valid,
                In_Ready          => In_Ready,
                In_Data           => In_Data,
                In_Last           => In_Last,
                In_User           => In_User,
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr,
                S_AxiLite_ArValid => Axi.read_address_channel.arvalid,
                S_AxiLite_ArReady => Axi.read_address_channel.arready,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr,
                S_AxiLite_AwValid => Axi.write_address_channel.awvalid,
                S_AxiLite_AwReady => Axi.write_address_channel.awready,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => Axi.write_data_channel.wvalid,
                S_AxiLite_WReady  => Axi.write_data_channel.wready,
                S_AxiLite_BResp   => Axi.write_response_channel.bresp,
                S_AxiLite_BValid  => Axi.write_response_channel.bvalid,
                S_AxiLite_BReady  => Axi.write_response_channel.bready,
                S_AxiLite_RData   => Axi.read_data_channel.rdata,
                S_AxiLite_RResp   => Axi.read_data_channel.rresp,
                S_AxiLite_RValid  => Axi.read_data_channel.rvalid,
                S_AxiLite_RReady  => Axi.read_data_channel.rready,
                Err_Framing       => Err_Framing(0),
                Stat_ImageOpen    => Stat_ImageOpen(0),
                Stat_EccSec       => Stat_EccSec(0),
                Stat_EccDed       => Stat_EccDed(0),
                Err_Config        => Err_Config(0),
                ErrInj_BitFlip    => ErrInj_BitFlip,
                ErrInj_Valid      => ErrInj_Valid
            );

        Err_Framing(1)    <= '0';
        Stat_ImageOpen(1) <= '0';
        Stat_EccSec(1)    <= '0';
        Stat_EccDed(1)    <= '0';
        Err_Config(1)     <= '0';

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Two filters in series (a separable kernel); the register slave belongs to the first
    -----------------------------------------------------------------------------------------------
    g_separable : if Separable_g generate
        signal Mid_Valid : std_logic;
        signal Mid_Ready : std_logic;
        signal Mid_Data  : std_logic_vector(B1_c - 1 downto 0);
        signal Mid_Last  : std_logic;
        signal Mid_User  : std_logic_vector(1 downto 0);
    begin

        i_dut1 : entity work.isp_filter2d
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
                Resource_g    => Resource_g,
                CoefBits_g    => CoefBits_g,
                Coef_g        => ispIntList(CoefStr_g),
                RuntimeCoef_g => RuntimeCoef_g,
                OutBits_g     => 0
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Valid          => In_Valid,
                In_Ready          => In_Ready,
                In_Data           => In_Data,
                In_Last           => In_Last,
                In_User           => In_User,
                Out_Valid         => Mid_Valid,
                Out_Ready         => Mid_Ready,
                Out_Data          => Mid_Data,
                Out_Last          => Mid_Last,
                Out_User          => Mid_User,
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr,
                S_AxiLite_ArValid => Axi.read_address_channel.arvalid,
                S_AxiLite_ArReady => Axi.read_address_channel.arready,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr,
                S_AxiLite_AwValid => Axi.write_address_channel.awvalid,
                S_AxiLite_AwReady => Axi.write_address_channel.awready,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => Axi.write_data_channel.wvalid,
                S_AxiLite_WReady  => Axi.write_data_channel.wready,
                S_AxiLite_BResp   => Axi.write_response_channel.bresp,
                S_AxiLite_BValid  => Axi.write_response_channel.bvalid,
                S_AxiLite_BReady  => Axi.write_response_channel.bready,
                S_AxiLite_RData   => Axi.read_data_channel.rdata,
                S_AxiLite_RResp   => Axi.read_data_channel.rresp,
                S_AxiLite_RValid  => Axi.read_data_channel.rvalid,
                S_AxiLite_RReady  => Axi.read_data_channel.rready,
                Err_Framing       => Err_Framing(0),
                Stat_ImageOpen    => Stat_ImageOpen(0),
                Stat_EccSec       => Stat_EccSec(0),
                Stat_EccDed       => Stat_EccDed(0),
                Err_Config        => Err_Config(0),
                ErrInj_BitFlip    => ErrInj_BitFlip,
                ErrInj_Valid      => ErrInj_Valid
            );

        i_dut2 : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => winOut(ImageWidth_g, WinX_g, StrideX_g),
                ImageHeight_g => winOut(ImageHeight_g, WinY_g, StrideY_g),
                PixelBits_g   => B1_c,
                WinX_g        => Win2X_g,
                WinY_g        => Win2Y_g,
                StrideX_g     => 1,
                StrideY_g     => 1,
                BorderMode_g  => BorderMode_g,
                EccPipeline_g => EccPipeline_g,
                Resource_g    => Resource_g,
                CoefBits_g    => CoefBits_g,
                Coef_g        => ispIntList(Coef2Str_g),
                RuntimeCoef_g => false,
                OutBits_g     => OutBits_g
            )
            port map (
                Clk            => Clk,
                Rst            => Rst,
                In_Valid       => Mid_Valid,
                In_Ready       => Mid_Ready,
                In_Data        => Mid_Data,
                In_Last        => Mid_Last,
                In_User        => Mid_User,
                Out_Valid      => Out_Valid,
                Out_Ready      => Out_Ready,
                Out_Data       => Out_Data,
                Out_Last       => Out_Last,
                Out_User       => Out_User,
                Err_Framing    => Err_Framing(1),
                Stat_ImageOpen => Stat_ImageOpen(1),
                Stat_EccSec    => Stat_EccSec(1),
                Stat_EccDed    => Stat_EccDed(1),
                Err_Config     => Err_Config(1)
            );

    end generate;

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
            Probe(0)  => Stat_ImageOpen(0),
            RstReq    => RstReq,
            Hold      => Hold,
            Marker    => Marker,
            Ack       => Ack,
            Done      => SrcDone
        );

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => B_c,
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
            Ack            => AckInj,
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
        disable_log_msg(ID_BFM);

        -- Every test runs its stimulus, register and injection files against the model; test_rate adds the timing
        -- checks
        while test_suite loop
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_static") or run("test_input_stream") or run("test_runtime") or run("test_errors") or
                  run("test_reset") then
                RateTest <= false;
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            ispRegsRun(RegsFile_g, ClkPeriod_c, Marker, AckRegs, Clk, Axi);

            wait until SrcDone and SinkDone;

            for i in 1 to Drain_c loop
                wait until rising_edge(Clk);
            end loop;

            check_value(Framing, ExpFraming_g, ERROR, "number of Err_Framing pulses");
            check_value(Sec, ExpSec_g, ERROR, "number of Stat_EccSec pulses");
            check_value(Ded, ExpDed_g, ERROR, "number of Stat_EccDed pulses");
            check_value(Config, ExpConfig_g, ERROR, "number of Err_Config pulses");
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
                   is_x(Stat_EccSec) or is_x(Stat_EccDed) or is_x(Err_Config) then
                    error("metavalue on a control output: In_Ready " & std_logic'image(In_Ready) &
                          ", Out_Valid " & std_logic'image(Out_Valid) & ", Err_Framing " & to_string(Err_Framing) &
                          ", Stat_ImageOpen " & to_string(Stat_ImageOpen) & ", Stat_EccSec " &
                          to_string(Stat_EccSec) & ", Stat_EccDed " & to_string(Stat_EccDed) & ", Err_Config " &
                          to_string(Err_Config));
                end if;
                if Out_Valid = '1' and is_x(Out_Data) then
                    error("metavalue in an output pixel");
                end if;
                if RstPrev_v = '1' and (Out_Valid /= '0' or Err_Framing /= "00" or Stat_ImageOpen /= "00" or
                                        Stat_EccSec /= "00" or Stat_EccDed /= "00" or Err_Config /= "00") then
                    error("after a reset: Out_Valid and the status outputs must be 0");
                end if;
                Framing <= Framing + count(Err_Framing);
                Sec     <= Sec + count(Stat_EccSec);
                Ded     <= Ded + count(Stat_EccDed);
                Config  <= Config + count(Err_Config);
            end if;
            if RstPrev_v = '1' and Rst = '0' then
                Started_v := true;
            end if;
            RstPrev_v := Rst;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Timing of test_rate (FLT-PF-01, FLT-PF-02), images back to back from the reset on
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
                        -- Image start: the interval from the image start before (FLT-PF-01 with WIN-PF-02); the
                        -- first interval after an idle module is shorter, every further one has the period
                        if ImgStart_v >= 0 then
                            if Periods_v = 0 then
                                check_value(Cycle - ImgStart_v <= Period_c, ERROR,
                                            "test_rate: first interval between two image starts " &
                                            integer'image(Cycle - ImgStart_v) & ", at most " &
                                            integer'image(Period_c) & " (FLT-PF-01)");
                            else
                                check_value(Cycle - ImgStart_v, Period_c, ERROR,
                                            "test_rate: interval between two image starts (FLT-PF-01)");
                            end if;
                            Periods_v := Periods_v + 1;
                        end if;
                        ImgStart_v := Cycle;
                    else
                        -- First pixel of a line: the hold cycles since the first pixel of the line before
                        -- (FLT-PF-01 with WIN-PF-01); line 1 of an image after an image also waits for the virtual
                        -- lines of the image before
                        Line_v := PixInImg_v / ImageWidth_g;
                        if Line_v = 1 and InN_v >= ImageWidth_g * ImageHeight_g then
                            check_value(Held_v <= HoldFirst_c, ERROR,
                                        "test_rate: " & integer'image(Held_v) & " hold cycles between the first " &
                                        "pixels of the first two lines, at most " & integer'image(HoldFirst_c) &
                                        " (FLT-PF-01)");
                        else
                            if Held_v > HeldMax_v then
                                HeldMax_v := Held_v;
                            end if;
                            check_value(Held_v <= HoldMax_c, ERROR,
                                        "test_rate: " & integer'image(Held_v) & " hold cycles between the first " &
                                        "pixels of two lines, at most " & integer'image(HoldMax_c) & " (FLT-PF-01)");
                        end if;
                    end if;
                    Held_v := 0;
                end if;
                InN_v := InN_v + 1;
            end if;

            -- Every output pixel: the input beat that completes its window, from the timing file of the model
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    Lat_v := Cycle - Acc_v(Src_v mod AccDepth_c);
                    check_value(Lat_v >= LatMin_c and Lat_v <= LatMax_c, ERROR,
                                "test_rate: latency " & integer'image(Lat_v) & " of output pixel " &
                                integer'image(OutN_v) & ", design " & integer'image(LatMin_c) & " to " &
                                integer'image(LatMax_c) & " (FLT-PF-02)");
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
