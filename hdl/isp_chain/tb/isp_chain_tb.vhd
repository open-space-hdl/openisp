---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Chain test of OpenISP (phase G): the modules of a chain connected output to input, as the user
-- guide describes. Chain_g "typical": isp_replace, isp_point, isp_crop, isp_filter2d, isp_bin,
-- isp_point (also the chain small); "reordered": isp_bin, isp_filter2d, isp_crop, isp_point. The
-- generics of every module behind the first follow from the module before through isp_pkg.
--
-- The shared source sends the stimulus at the chain input (through an olo_ft_fifo_sync with
-- FifoDepth_g > 0), the shared sink compares the chain output with the composed model, and a
-- contract monitor observes every connection between two modules. An AXI4-Lite decoder gives each
-- module a slot (address bits 15 to 12: 0 isp_replace, 1 the first isp_point, 2 isp_crop, 3
-- isp_filter2d, 4 the second isp_point; in "reordered" its isp_point is slot 1). One injection
-- script per ECC port, a module reset script, the pulse counters of every module checked against
-- the model, an olo_ft_ecc_monitor with one channel per ECC source, and the timing of test_rate and
-- test_fifo against the design values of the verification plan (section 5).
--
-- Positions (index in the chain) number the pulse counters, the contract monitors (monitor j on the
-- output of position j) and the module resets; ExpPulses_g lists per position the numbers of
-- Err_Framing, Err_Config, Stat_EccSec, Stat_EccDed, Stat_Unreplaced, Scrub_EccSec, (unused),
-- Scrub_Overrun pulses.
--
-- Documentation: hdl/isp_chain/docs/verification_plan.md

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
entity isp_chain_tb is
    generic (
        runner_cfg      : string;
        Chain_g         : string   := "typical";
        -- Input of the chain
        Width_g         : positive := 40;
        Height_g        : positive := 20;
        Bits_g          : positive := 12;
        -- isp_replace
        RplGap_g        : natural  := 2;
        RplLat_g        : positive := 1;
        RplEcc_g        : natural  := 0;
        -- First isp_point (typical): output bits and multiplier stages; both isp_point have run-time parameters
        P1Bits_g        : positive := 12;
        P1Stages_g      : positive := 2;
        GainBits_g      : positive := 16;
        -- isp_crop
        CrpWidth_g      : positive := 32;
        CrpHeight_g     : positive := 16;
        CrpX_g          : natural  := 4;
        CrpY_g          : natural  := 2;
        CrpRuntime_g    : boolean  := true;
        -- isp_filter2d (square window)
        FltWin_g        : positive := 3;
        FltBorder_g     : string   := "replicate";
        FltCoefBits_g   : positive := 16;
        FltCoef_g       : string   := "-1,-2,-1,-2,28,-2,-1,-2,-1";
        FltRuntime_g    : boolean  := true;
        FltOutBits_g    : natural  := 16;
        FltResource_g   : string   := "AUTO";
        FltEcc_g        : natural  := 1;
        -- isp_bin
        BinX_g          : positive := 2;
        BinY_g          : positive := 2;
        BinBorder_g     : string   := "valid";
        BinResource_g   : string   := "AUTO";
        BinEcc_g        : natural  := 1;
        -- Last isp_point: output bits, shift of its generics, run-time parameters, multiplier stages
        P2Bits_g        : positive := 12;
        P2Shift_g       : natural  := 6;
        P2Runtime_g     : boolean  := true;
        P2Stages_g      : positive := 2;
        -- FIFO in front of the chain (0: none) and its largest fill level (In_Level) in test_fifo
        FifoDepth_g     : natural  := 0;
        FifoLevel_g     : natural  := 0;
        -- Files of the test
        StimFile_g      : string;
        ExpFile_g       : string;
        RegsFile_g      : string;
        InjRplFile_g    : string;
        InjFltFile_g    : string;
        InjBinFile_g    : string;
        ModRstFile_g    : string;
        TimFile_g       : string;
        GapPct_g        : natural  := 0;
        StallPct_g      : natural  := 0;
        Seed_g          : positive := 1;
        -- Numbers of the pulses of the model, 8 per position (see the description)
        ExpPulses_g     : string;
        -- Scrub_Enable of isp_replace at the start, and its words with a double error (Scrub_EccDed per pass)
        ScrubAtStart_g  : boolean  := true;
        ScrubDedWords_g : natural  := 0;
        -- Design values of test_rate (verification plan, sections 5.1 and 5.2): hold cycles at the chain input
        -- between the first pixels of two lines, between lines 0 and 1 of the first image and of every image after
        -- it, the first and every further interval between two image starts, the latency of an output pixel
        HoldLine_g      : natural  := 0;
        HoldFirst_g     : natural  := 0;
        HoldWait_g      : natural  := 0;
        PerFirst_g      : natural  := 0;
        Per_g           : natural  := 0;
        LatMin_g        : natural  := 0;
        LatMax_g        : natural  := 0;
        -- Negative tests: the contract monitor of this position one pixel short (-1: none); the beat of this index
        -- between isp_crop and the module behind it with its data bits inverted by NegMask_g (-1: none); the number
        -- of errors the provocation causes (expected alerts)
        NegSeam_g       : integer  := -1;
        NegBeat_g       : integer  := -1;
        NegMask_g       : natural  := 1;
        ExpErrors_g     : natural  := 0;
        -- Watchdog: the test fails when it has not ended after this time (docs/testbench.md, section 6)
        WatchdogUs_g    : positive := 1000
    );
end entity;

architecture sim of isp_chain_tb is

    constant ClkPeriod_c : time           := 10 ns;
    constant Typical_c   : boolean        := Chain_g = "typical";
    constant Stages_c    : positive       := choose(Typical_c, 6, 4);
    constant Kinds_c     : positive       := 8;
    constant Exp_c       : integer_vector := ispIntList(ExpPulses_g);
    constant Taps_c      : positive       := FltWin_g * FltWin_g;

    -- Pixel bits and dimensions along the chain (user guide 5.1, through the functions of isp_pkg)
    -- typical: replace (Bits) -> point (P1Bits) -> crop -> filter2d (FltB) -> bin (BinB) -> point (P2Bits)
    constant TFltIn_c : positive := P1Bits_g;
    constant TFltB_c  : positive := ispConvOutBits(TFltIn_c, FltCoefBits_g, Taps_c, FltOutBits_g);
    constant TFltW_c  : positive := maximum(ispWinOut(CrpWidth_g, FltWin_g, 1, FltBorder_g), 1);
    constant TFltH_c  : positive := maximum(ispWinOut(CrpHeight_g, FltWin_g, 1, FltBorder_g), 1);
    constant TBinB_c  : positive := TFltB_c + log2ceil(BinX_g * BinY_g);
    constant TBinW_c  : positive := maximum(ispBinOut(TFltW_c, BinX_g, BinBorder_g), 1);
    constant TBinH_c  : positive := maximum(ispBinOut(TFltH_c, BinY_g, BinBorder_g), 1);
    -- reordered: bin (BinB) -> filter2d (FltB) -> crop -> point (P2Bits)
    constant RBinB_c  : positive := Bits_g + log2ceil(BinX_g * BinY_g);
    constant RBinW_c  : positive := maximum(ispBinOut(Width_g, BinX_g, BinBorder_g), 1);
    constant RBinH_c  : positive := maximum(ispBinOut(Height_g, BinY_g, BinBorder_g), 1);
    constant RFltB_c  : positive := ispConvOutBits(RBinB_c, FltCoefBits_g, Taps_c, FltOutBits_g);
    constant RFltW_c  : positive := maximum(ispWinOut(RBinW_c, FltWin_g, 1, FltBorder_g), 1);
    constant RFltH_c  : positive := maximum(ispWinOut(RBinH_c, FltWin_g, 1, FltBorder_g), 1);
    -- Output of the chain
    constant OutW_c   : positive := choose(Typical_c, TBinW_c, CrpWidth_g);
    constant OutH_c   : positive := choose(Typical_c, TBinH_c, CrpHeight_g);

    -- Input dimensions of every position (the dimensions of the contract monitor in front of it)
    type Dims_t is array (0 to 5) of natural;

    function inWidths return Dims_t is
    begin
        if Typical_c then
            return (Width_g, Width_g, Width_g, CrpWidth_g, TFltW_c, TBinW_c);
        end if;
        return (Width_g, RBinW_c, RFltW_c, CrpWidth_g, 0, 0);
    end function;

    function inHeights return Dims_t is
    begin
        if Typical_c then
            return (Height_g, Height_g, Height_g, CrpHeight_g, TFltH_c, TBinH_c);
        end if;
        return (Height_g, RBinH_c, RFltH_c, CrpHeight_g, 0, 0);
    end function;

    constant InW_c : Dims_t := inWidths;
    constant InH_c : Dims_t := inHeights;

    -- ECC injection widths
    constant RplFlipW_c : positive := eccCodewordWidth(32);
    constant FltFlipW_c : positive := maximum(FltWin_g - 1, 1) * eccCodewordWidth(choose(Typical_c, TFltIn_c, RBinB_c));
    constant BinFlipW_c : positive := maximum(BinY_g - 1, 1) *
                                      eccCodewordWidth(choose(Typical_c, TFltB_c, Bits_g) + log2ceil(BinX_g));

    -- Kinds of the pulse counters
    constant KFraming_c  : natural := 0;
    constant KConfig_c   : natural := 1;
    constant KSec_c      : natural := 2;
    constant KDed_c      : natural := 3;
    constant KUnrepl_c   : natural := 4;
    constant KScrubSec_c : natural := 5;
    constant KScrubDed_c : natural := 6;
    constant KOverrun_c  : natural := 7;

    -- AXI4-Lite slots of the decoder
    constant Slots_c : positive := 5;

    type SlvIn_t is record
        ArValid : std_logic;
        AwValid : std_logic;
        WValid  : std_logic;
        BReady  : std_logic;
        RReady  : std_logic;
    end record;

    type SlvOut_t is record
        ArReady : std_logic;
        AwReady : std_logic;
        WReady  : std_logic;
        BValid  : std_logic;
        BResp   : std_logic_vector(1 downto 0);
        RValid  : std_logic;
        RResp   : std_logic_vector(1 downto 0);
        RData   : std_logic_vector(31 downto 0);
    end record;

    constant SlvOutIdle_c : SlvOut_t := ('0', '0', '0', '0', "00", '0', "00", (others => '0'));

    type SlvIn_a is array (0 to Slots_c - 1) of SlvIn_t;
    type SlvOut_a is array (0 to Slots_c - 1) of SlvOut_t;

    type Counts_t is array (0 to 6 * Kinds_c - 1) of natural;

    signal Clk     : std_logic := '0';
    signal Rst     : std_logic;
    signal InitRst : std_logic := '1';
    signal RstReq  : std_logic;
    -- Reset of every position: the common reset or its own (module reset script)
    signal ModReq  : std_logic_vector(0 to 5) := (others => '0');
    signal ModRst  : std_logic_vector(0 to 5);

    -- Source and chain input
    signal Src_Valid : std_logic;
    signal Src_Ready : std_logic;
    signal Src_Data  : std_logic_vector(Bits_g - 1 downto 0);
    signal Src_Last  : std_logic;
    signal Src_User  : std_logic_vector(1 downto 0);
    signal In_Valid  : std_logic;
    signal In_Ready  : std_logic;
    signal In_Data   : std_logic_vector(Bits_g - 1 downto 0);
    signal In_Last   : std_logic;
    signal In_User   : std_logic_vector(1 downto 0);
    signal FifoLevel : natural := 0;

    -- Chain output
    signal Out_Valid : std_logic;
    signal Out_Ready : std_logic;
    signal Out_Data  : std_logic_vector(P2Bits_g - 1 downto 0);
    signal Out_Last  : std_logic;
    signal Out_User  : std_logic_vector(1 downto 0);

    -- Handshake and flags of every connection: SeamV(j) etc. at the output of position j
    signal SeamV : std_logic_vector(0 to 5) := (others => '0');
    signal SeamR : std_logic_vector(0 to 5) := (others => '0');
    signal SeamL : std_logic_vector(0 to 5) := (others => '0');
    type Flags_a is array (0 to 5) of std_logic_vector(1 downto 0);

    signal SeamU : Flags_a := (others => "00");

    -- Status of every position: In_Ready, Out_Valid, Stat_ImageOpen, the pulses in the order of the kinds
    signal Ready  : std_logic_vector(0 to 5)               := (others => '0');
    signal Valid  : std_logic_vector(0 to 5)               := (others => '0');
    signal Opened : std_logic_vector(0 to 5)               := (others => '0');
    signal Pulses : std_logic_vector(0 to 6 * Kinds_c - 1) := (others => '0');
    signal PassDn : std_logic                              := '0';

    -- AXI4-Lite of the BFM (16 address bits) and of the slots
    signal Axi : t_axilite_if(
                               write_address_channel(
                                                        awaddr(15 downto 0)),
                               write_data_channel(
                                                     wdata(31 downto 0),
                                                     wstrb(3 downto 0)),
                               read_address_channel(
                                                       araddr(15 downto 0)),
                               read_data_channel(
                                                    rdata(31 downto 0))) := init_axilite_if_signals(16, 32);

    signal SIn   : SlvIn_a;
    signal SOut  : SlvOut_a              := (others => SlvOutIdle_c);
    signal WSelR : natural range 0 to 15 := 0;
    signal RSelR : natural range 0 to 15 := 0;
    signal WSel  : natural range 0 to 15;
    signal RSel  : natural range 0 to 15;

    -- ECC injection of isp_replace (map), isp_filter2d and isp_bin
    signal RplFlip   : std_logic_vector(RplFlipW_c - 1 downto 0);
    signal RplInj    : std_logic;
    signal FltFlip   : std_logic_vector(FltFlipW_c - 1 downto 0);
    signal FltInj    : std_logic;
    signal BinFlip   : std_logic_vector(BinFlipW_c - 1 downto 0);
    signal BinInj    : std_logic;
    signal ScrubReq  : std_logic;
    signal ScrubOn   : std_logic := '0';
    signal Scrub_Ena : std_logic;
    signal FltScrub  : std_logic;
    signal BinScrub  : std_logic;

    -- ECC monitor (channels: 0 isp_replace, 1 its scrubber, 2 isp_filter2d, 3 isp_bin)
    signal MonSec    : std_logic_vector(3 downto 0);
    signal MonDed    : std_logic_vector(3 downto 0);
    signal MonRdCh   : std_logic_vector(1 downto 0) := "00";
    signal MonRdEna  : std_logic                    := '0';
    signal MonSecCnt : std_logic_vector(15 downto 0);
    signal MonDedCnt : std_logic_vector(15 downto 0);
    signal MonRdVld  : std_logic;

    signal SinkCount : natural;
    signal SrcDone   : boolean;
    signal SinkDone  : boolean;
    signal Hold      : std_logic;
    signal Marker    : natural;
    -- Acknowledges of the scripts; the source waits for the largest
    signal AckRegs   : natural := 0;
    signal AckRpl    : natural;
    signal AckFlt    : natural;
    signal AckBin    : natural;
    signal AckRst    : natural := 0;
    signal Ack       : natural;

    signal Counts   : Counts_t := (others => 0);
    signal PassDone : natural  := 0;
    signal Cycle    : natural  := 0;
    signal RateTest : boolean  := false;
    signal FifoTest : boolean  := false;
    signal RegsTest : boolean  := false;

    -- Inverts the data bits of beat NegBeat_g at the connection behind isp_crop
    signal NegCount : natural := 0;

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        end if;
        return '0';
    end function;

    function scrubStart return std_logic is
    begin
        return toSl(ScrubAtStart_g);
    end function;

begin

    assert Chain_g = "typical" or Chain_g = "reordered"
        report "isp_chain_tb: Chain_g must be typical or reordered"
        severity failure;

    Clk <= not Clk after ClkPeriod_c / 2;
    Rst <= InitRst or RstReq;
    Ack <= maximum(maximum(AckRegs, AckRpl), maximum(maximum(AckFlt, AckBin), AckRst));

    g_rst : for i in 0 to 5 generate
        ModRst(i) <= Rst or ModReq(i);
    end generate;

    test_runner_watchdog(runner, WatchdogUs_g * 1 us);

    -----------------------------------------------------------------------------------------------
    -- Source, optional FIFO, sink
    -----------------------------------------------------------------------------------------------
    i_source : entity work.isp_tb_source
        generic map (
            Width_g      => Bits_g,
            StimFile_g   => StimFile_g,
            GapPct_g     => GapPct_g,
            Seed_g       => Seed_g,
            ProbeWidth_g => 1
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            M_Valid   => Src_Valid,
            M_Ready   => Src_Ready,
            M_Data    => Src_Data,
            M_Last    => Src_Last,
            M_User    => Src_User,
            SinkCount => SinkCount,
            Probe(0)  => Opened(0),
            RstReq    => RstReq,
            Hold      => Hold,
            Marker    => Marker,
            Ack       => Ack,
            Done      => SrcDone
        );

    g_nofifo : if FifoDepth_g = 0 generate
        In_Valid  <= Src_Valid;
        Src_Ready <= In_Ready;
        In_Data   <= Src_Data;
        In_Last   <= Src_Last;
        In_User   <= Src_User;
    end generate;

    g_fifo : if FifoDepth_g > 0 generate
        signal FIn   : std_logic_vector(Bits_g + 2 downto 0);
        signal FOut  : std_logic_vector(Bits_g + 2 downto 0);
        signal Level : std_logic_vector(log2ceil(FifoDepth_g + 1) - 1 downto 0);
    begin
        FIn <= Src_User & Src_Last & Src_Data;

        i_fifo : entity olo.olo_ft_fifo_sync
            generic map (
                Width_g => Bits_g + 3,
                Depth_g => FifoDepth_g
            )
            port map (
                Clk       => Clk,
                Rst       => Rst,
                In_Data   => FIn,
                In_Valid  => Src_Valid,
                In_Ready  => Src_Ready,
                In_Level  => Level,
                Out_Data  => FOut,
                Out_Valid => In_Valid,
                Out_Ready => In_Ready
            );

        In_Data   <= FOut(Bits_g - 1 downto 0);
        In_Last   <= FOut(Bits_g);
        In_User   <= FOut(Bits_g + 2 downto Bits_g + 1);
        FifoLevel <= to_integer(unsigned(Level));
    end generate;

    i_sink : entity work.isp_tb_sink
        generic map (
            Width_g     => P2Bits_g,
            SideWidth_g => 1,
            ExpFile_g   => ExpFile_g,
            StallPct_g  => StallPct_g,
            Seed_g      => Seed_g + 1,
            OutWidth_g  => OutW_c,
            OutHeight_g => OutH_c
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

    -----------------------------------------------------------------------------------------------
    -- Contract monitors of the connections: monitor j observes the output of position j with the
    -- input dimensions of position j + 1 and restarts with the reset of position j
    -----------------------------------------------------------------------------------------------
    g_monitors : for j in 0 to Stages_c - 2 generate
        constant Name_c : string := "connection " & integer'image(j) & " -> " & integer'image(j + 1);
    begin

        i_monitor : entity work.isp_tb_monitor
            generic map (
                Width_g  => InW_c(j + 1) - choose(NegSeam_g = j, 1, 0),
                Height_g => InH_c(j + 1),
                Name_g   => Name_c
            )
            port map (
                Clk     => Clk,
                Rst     => ModRst(j),
                S_Valid => SeamV(j),
                S_Ready => SeamR(j),
                S_Last  => SeamL(j),
                S_User  => SeamU(j)
            );

    end generate;

    -----------------------------------------------------------------------------------------------
    -- Chain typical: isp_replace, isp_point, isp_crop, isp_filter2d, isp_bin, isp_point
    -----------------------------------------------------------------------------------------------
    g_typical : if Typical_c generate
        -- Connections: Dn the output of position n
        signal D0    : std_logic_vector(Bits_g - 1 downto 0);
        signal D1    : std_logic_vector(P1Bits_g - 1 downto 0);
        signal D2    : std_logic_vector(P1Bits_g - 1 downto 0);
        signal D2Neg : std_logic_vector(P1Bits_g - 1 downto 0);
        signal D3    : std_logic_vector(TFltB_c - 1 downto 0);
        signal D4    : std_logic_vector(TBinB_c - 1 downto 0);
    begin

        i_replace : entity work.isp_replace
            generic map (
                ImageWidth_g   => Width_g,
                ImageHeight_g  => Height_g,
                PixelBits_g    => Bits_g,
                MaxGap_g       => RplGap_g,
                RamRdLatency_g => RplLat_g,
                EccPipeline_g  => RplEcc_g,
                ClkFreqHz_g    => 100.0e6,
                ScrubPeriod_g  => 0.0
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(0),
                In_Valid          => In_Valid,
                In_Ready          => In_Ready,
                In_Data           => In_Data,
                In_Last           => In_Last,
                In_User           => In_User,
                Out_Valid         => SeamV(0),
                Out_Ready         => SeamR(0),
                Out_Data          => D0,
                Out_Last          => SeamL(0),
                Out_User          => SeamU(0),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(0).ArValid,
                S_AxiLite_ArReady => SOut(0).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(0).AwValid,
                S_AxiLite_AwReady => SOut(0).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(0).WValid,
                S_AxiLite_WReady  => SOut(0).WReady,
                S_AxiLite_BResp   => SOut(0).BResp,
                S_AxiLite_BValid  => SOut(0).BValid,
                S_AxiLite_BReady  => SIn(0).BReady,
                S_AxiLite_RData   => SOut(0).RData,
                S_AxiLite_RResp   => SOut(0).RResp,
                S_AxiLite_RValid  => SOut(0).RValid,
                S_AxiLite_RReady  => SIn(0).RReady,
                Err_Framing       => Pulses(0 * Kinds_c + KFraming_c),
                Stat_ImageOpen    => Opened(0),
                Stat_Unreplaced   => Pulses(0 * Kinds_c + KUnrepl_c),
                Stat_EccSec       => Pulses(0 * Kinds_c + KSec_c),
                Stat_EccDed       => Pulses(0 * Kinds_c + KDed_c),
                ErrInj_BitFlip    => RplFlip,
                ErrInj_Valid      => RplInj,
                Scrub_Enable      => Scrub_Ena,
                Scrub_EccSec      => Pulses(0 * Kinds_c + KScrubSec_c),
                Scrub_EccDed      => Pulses(0 * Kinds_c + KScrubDed_c),
                Scrub_PassDone    => PassDn,
                Scrub_Overrun     => Pulses(0 * Kinds_c + KOverrun_c)
            );

        i_point1 : entity work.isp_point
            generic map (
                ImageWidth_g  => Width_g,
                ImageHeight_g => Height_g,
                InBits_g      => Bits_g,
                OutBits_g     => P1Bits_g,
                GainBits_g    => GainBits_g,
                MaxShift_g    => Bits_g + GainBits_g,
                Runtime_g     => true,
                MultStages_g  => P1Stages_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(1),
                In_Valid          => SeamV(0),
                In_Ready          => SeamR(0),
                In_Data           => D0,
                In_Last           => SeamL(0),
                In_User           => SeamU(0),
                Out_Valid         => SeamV(1),
                Out_Ready         => SeamR(1),
                Out_Data          => D1,
                Out_Last          => SeamL(1),
                Out_User          => SeamU(1),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(1).ArValid,
                S_AxiLite_ArReady => SOut(1).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(1).AwValid,
                S_AxiLite_AwReady => SOut(1).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(1).WValid,
                S_AxiLite_WReady  => SOut(1).WReady,
                S_AxiLite_BResp   => SOut(1).BResp,
                S_AxiLite_BValid  => SOut(1).BValid,
                S_AxiLite_BReady  => SIn(1).BReady,
                S_AxiLite_RData   => SOut(1).RData,
                S_AxiLite_RResp   => SOut(1).RResp,
                S_AxiLite_RValid  => SOut(1).RValid,
                S_AxiLite_RReady  => SIn(1).RReady,
                Err_Framing       => Pulses(1 * Kinds_c + KFraming_c),
                Err_Config        => Pulses(1 * Kinds_c + KConfig_c),
                Stat_ImageOpen    => Opened(1)
            );

        i_crop : entity work.isp_crop
            generic map (
                ImageWidth_g  => Width_g,
                ImageHeight_g => Height_g,
                PixelBits_g   => P1Bits_g,
                RoiWidth_g    => CrpWidth_g,
                RoiHeight_g   => CrpHeight_g,
                RoiX_g        => CrpX_g,
                RoiY_g        => CrpY_g,
                RuntimeRoi_g  => CrpRuntime_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(2),
                In_Valid          => SeamV(1),
                In_Ready          => SeamR(1),
                In_Data           => D1,
                In_Last           => SeamL(1),
                In_User           => SeamU(1),
                Out_Valid         => SeamV(2),
                Out_Ready         => SeamR(2),
                Out_Data          => D2,
                Out_Last          => SeamL(2),
                Out_User          => SeamU(2),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(2).ArValid,
                S_AxiLite_ArReady => SOut(2).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(2).AwValid,
                S_AxiLite_AwReady => SOut(2).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(2).WValid,
                S_AxiLite_WReady  => SOut(2).WReady,
                S_AxiLite_BResp   => SOut(2).BResp,
                S_AxiLite_BValid  => SOut(2).BValid,
                S_AxiLite_BReady  => SIn(2).BReady,
                S_AxiLite_RData   => SOut(2).RData,
                S_AxiLite_RResp   => SOut(2).RResp,
                S_AxiLite_RValid  => SOut(2).RValid,
                S_AxiLite_RReady  => SIn(2).RReady,
                Err_Framing       => Pulses(2 * Kinds_c + KFraming_c),
                Err_Config        => Pulses(2 * Kinds_c + KConfig_c),
                Stat_ImageOpen    => Opened(2)
            );

        -- Negative test neg_seam_beat: the data bits of one beat behind isp_crop inverted
        D2Neg <= D2 xor std_logic_vector(to_unsigned(NegMask_g, P1Bits_g)) when NegCount = NegBeat_g else D2;

        i_filter2d : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => CrpWidth_g,
                ImageHeight_g => CrpHeight_g,
                PixelBits_g   => TFltIn_c,
                WinX_g        => FltWin_g,
                WinY_g        => FltWin_g,
                BorderMode_g  => FltBorder_g,
                EccPipeline_g => FltEcc_g,
                Resource_g    => FltResource_g,
                CoefBits_g    => FltCoefBits_g,
                Coef_g        => ispIntList(FltCoef_g),
                RuntimeCoef_g => FltRuntime_g,
                OutBits_g     => FltOutBits_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(3),
                In_Valid          => SeamV(2),
                In_Ready          => SeamR(2),
                In_Data           => D2Neg,
                In_Last           => SeamL(2),
                In_User           => SeamU(2),
                Out_Valid         => SeamV(3),
                Out_Ready         => SeamR(3),
                Out_Data          => D3,
                Out_Last          => SeamL(3),
                Out_User          => SeamU(3),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(11 downto 0),
                S_AxiLite_ArValid => SIn(3).ArValid,
                S_AxiLite_ArReady => SOut(3).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(11 downto 0),
                S_AxiLite_AwValid => SIn(3).AwValid,
                S_AxiLite_AwReady => SOut(3).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(3).WValid,
                S_AxiLite_WReady  => SOut(3).WReady,
                S_AxiLite_BResp   => SOut(3).BResp,
                S_AxiLite_BValid  => SOut(3).BValid,
                S_AxiLite_BReady  => SIn(3).BReady,
                S_AxiLite_RData   => SOut(3).RData,
                S_AxiLite_RResp   => SOut(3).RResp,
                S_AxiLite_RValid  => SOut(3).RValid,
                S_AxiLite_RReady  => SIn(3).RReady,
                Err_Framing       => Pulses(3 * Kinds_c + KFraming_c),
                Stat_ImageOpen    => Opened(3),
                Stat_EccSec       => Pulses(3 * Kinds_c + KSec_c),
                Stat_EccDed       => Pulses(3 * Kinds_c + KDed_c),
                Err_Config        => Pulses(3 * Kinds_c + KConfig_c),
                ErrInj_BitFlip    => FltFlip,
                ErrInj_Valid      => FltInj
            );

        i_bin : entity work.isp_bin
            generic map (
                ImageWidth_g  => TFltW_c,
                ImageHeight_g => TFltH_c,
                PixelBits_g   => TFltB_c,
                BinX_g        => BinX_g,
                BinY_g        => BinY_g,
                BorderMode_g  => BinBorder_g,
                EccPipeline_g => BinEcc_g,
                Resource_g    => BinResource_g
            )
            port map (
                Clk            => Clk,
                Rst            => ModRst(4),
                In_Valid       => SeamV(3),
                In_Ready       => SeamR(3),
                In_Data        => D3,
                In_Last        => SeamL(3),
                In_User        => SeamU(3),
                Out_Valid      => SeamV(4),
                Out_Ready      => SeamR(4),
                Out_Data       => D4,
                Out_Last       => SeamL(4),
                Out_User       => SeamU(4),
                Err_Framing    => Pulses(4 * Kinds_c + KFraming_c),
                Stat_ImageOpen => Opened(4),
                Stat_EccSec    => Pulses(4 * Kinds_c + KSec_c),
                Stat_EccDed    => Pulses(4 * Kinds_c + KDed_c),
                ErrInj_BitFlip => BinFlip,
                ErrInj_Valid   => BinInj
            );

        i_point2 : entity work.isp_point
            generic map (
                ImageWidth_g  => TBinW_c,
                ImageHeight_g => TBinH_c,
                InBits_g      => TBinB_c,
                OutBits_g     => P2Bits_g,
                GainBits_g    => GainBits_g,
                MaxShift_g    => TBinB_c + GainBits_g,
                Shift_g       => P2Shift_g,
                Runtime_g     => P2Runtime_g,
                MultStages_g  => P2Stages_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(5),
                In_Valid          => SeamV(4),
                In_Ready          => SeamR(4),
                In_Data           => D4,
                In_Last           => SeamL(4),
                In_User           => SeamU(4),
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(4).ArValid,
                S_AxiLite_ArReady => SOut(4).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(4).AwValid,
                S_AxiLite_AwReady => SOut(4).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(4).WValid,
                S_AxiLite_WReady  => SOut(4).WReady,
                S_AxiLite_BResp   => SOut(4).BResp,
                S_AxiLite_BValid  => SOut(4).BValid,
                S_AxiLite_BReady  => SIn(4).BReady,
                S_AxiLite_RData   => SOut(4).RData,
                S_AxiLite_RResp   => SOut(4).RResp,
                S_AxiLite_RValid  => SOut(4).RValid,
                S_AxiLite_RReady  => SIn(4).RReady,
                Err_Framing       => Pulses(5 * Kinds_c + KFraming_c),
                Err_Config        => Pulses(5 * Kinds_c + KConfig_c),
                Stat_ImageOpen    => Opened(5)
            );

        Ready(0 to 5) <= In_Ready & SeamR(0 to 4);
        Valid(0 to 5) <= SeamV(0 to 4) & Out_Valid;

        -- ECC monitor channels
        MonSec <= Pulses(4 * Kinds_c + KSec_c) & Pulses(3 * Kinds_c + KSec_c) & Pulses(0 * Kinds_c + KScrubSec_c) &
                  Pulses(0 * Kinds_c + KSec_c);
        MonDed <= Pulses(4 * Kinds_c + KDed_c) & Pulses(3 * Kinds_c + KDed_c) & Pulses(0 * Kinds_c + KScrubDed_c) &
                  Pulses(0 * Kinds_c + KDed_c);
    end generate;

    -----------------------------------------------------------------------------------------------
    -- Chain reordered: isp_bin, isp_filter2d, isp_crop, isp_point
    -----------------------------------------------------------------------------------------------
    g_reordered : if not Typical_c generate
        signal D0 : std_logic_vector(RBinB_c - 1 downto 0);
        signal D1 : std_logic_vector(RFltB_c - 1 downto 0);
        signal D2 : std_logic_vector(RFltB_c - 1 downto 0);
    begin

        i_bin : entity work.isp_bin
            generic map (
                ImageWidth_g  => Width_g,
                ImageHeight_g => Height_g,
                PixelBits_g   => Bits_g,
                BinX_g        => BinX_g,
                BinY_g        => BinY_g,
                BorderMode_g  => BinBorder_g,
                EccPipeline_g => BinEcc_g,
                Resource_g    => BinResource_g
            )
            port map (
                Clk            => Clk,
                Rst            => ModRst(0),
                In_Valid       => In_Valid,
                In_Ready       => In_Ready,
                In_Data        => In_Data,
                In_Last        => In_Last,
                In_User        => In_User,
                Out_Valid      => SeamV(0),
                Out_Ready      => SeamR(0),
                Out_Data       => D0,
                Out_Last       => SeamL(0),
                Out_User       => SeamU(0),
                Err_Framing    => Pulses(0 * Kinds_c + KFraming_c),
                Stat_ImageOpen => Opened(0),
                Stat_EccSec    => Pulses(0 * Kinds_c + KSec_c),
                Stat_EccDed    => Pulses(0 * Kinds_c + KDed_c),
                ErrInj_BitFlip => BinFlip,
                ErrInj_Valid   => BinInj
            );

        i_filter2d : entity work.isp_filter2d
            generic map (
                ImageWidth_g  => RBinW_c,
                ImageHeight_g => RBinH_c,
                PixelBits_g   => RBinB_c,
                WinX_g        => FltWin_g,
                WinY_g        => FltWin_g,
                BorderMode_g  => FltBorder_g,
                EccPipeline_g => FltEcc_g,
                Resource_g    => FltResource_g,
                CoefBits_g    => FltCoefBits_g,
                Coef_g        => ispIntList(FltCoef_g),
                RuntimeCoef_g => FltRuntime_g,
                OutBits_g     => FltOutBits_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(1),
                In_Valid          => SeamV(0),
                In_Ready          => SeamR(0),
                In_Data           => D0,
                In_Last           => SeamL(0),
                In_User           => SeamU(0),
                Out_Valid         => SeamV(1),
                Out_Ready         => SeamR(1),
                Out_Data          => D1,
                Out_Last          => SeamL(1),
                Out_User          => SeamU(1),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(11 downto 0),
                S_AxiLite_ArValid => SIn(3).ArValid,
                S_AxiLite_ArReady => SOut(3).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(11 downto 0),
                S_AxiLite_AwValid => SIn(3).AwValid,
                S_AxiLite_AwReady => SOut(3).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(3).WValid,
                S_AxiLite_WReady  => SOut(3).WReady,
                S_AxiLite_BResp   => SOut(3).BResp,
                S_AxiLite_BValid  => SOut(3).BValid,
                S_AxiLite_BReady  => SIn(3).BReady,
                S_AxiLite_RData   => SOut(3).RData,
                S_AxiLite_RResp   => SOut(3).RResp,
                S_AxiLite_RValid  => SOut(3).RValid,
                S_AxiLite_RReady  => SIn(3).RReady,
                Err_Framing       => Pulses(1 * Kinds_c + KFraming_c),
                Stat_ImageOpen    => Opened(1),
                Stat_EccSec       => Pulses(1 * Kinds_c + KSec_c),
                Stat_EccDed       => Pulses(1 * Kinds_c + KDed_c),
                Err_Config        => Pulses(1 * Kinds_c + KConfig_c),
                ErrInj_BitFlip    => FltFlip,
                ErrInj_Valid      => FltInj
            );

        i_crop : entity work.isp_crop
            generic map (
                ImageWidth_g  => RFltW_c,
                ImageHeight_g => RFltH_c,
                PixelBits_g   => RFltB_c,
                RoiWidth_g    => CrpWidth_g,
                RoiHeight_g   => CrpHeight_g,
                RoiX_g        => CrpX_g,
                RoiY_g        => CrpY_g,
                RuntimeRoi_g  => CrpRuntime_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(2),
                In_Valid          => SeamV(1),
                In_Ready          => SeamR(1),
                In_Data           => D1,
                In_Last           => SeamL(1),
                In_User           => SeamU(1),
                Out_Valid         => SeamV(2),
                Out_Ready         => SeamR(2),
                Out_Data          => D2,
                Out_Last          => SeamL(2),
                Out_User          => SeamU(2),
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(2).ArValid,
                S_AxiLite_ArReady => SOut(2).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(2).AwValid,
                S_AxiLite_AwReady => SOut(2).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(2).WValid,
                S_AxiLite_WReady  => SOut(2).WReady,
                S_AxiLite_BResp   => SOut(2).BResp,
                S_AxiLite_BValid  => SOut(2).BValid,
                S_AxiLite_BReady  => SIn(2).BReady,
                S_AxiLite_RData   => SOut(2).RData,
                S_AxiLite_RResp   => SOut(2).RResp,
                S_AxiLite_RValid  => SOut(2).RValid,
                S_AxiLite_RReady  => SIn(2).RReady,
                Err_Framing       => Pulses(2 * Kinds_c + KFraming_c),
                Err_Config        => Pulses(2 * Kinds_c + KConfig_c),
                Stat_ImageOpen    => Opened(2)
            );

        i_point : entity work.isp_point
            generic map (
                ImageWidth_g  => CrpWidth_g,
                ImageHeight_g => CrpHeight_g,
                InBits_g      => RFltB_c,
                OutBits_g     => P2Bits_g,
                GainBits_g    => GainBits_g,
                MaxShift_g    => RFltB_c + GainBits_g,
                Shift_g       => P2Shift_g,
                Runtime_g     => P2Runtime_g,
                MultStages_g  => P2Stages_g
            )
            port map (
                Clk               => Clk,
                Rst               => ModRst(3),
                In_Valid          => SeamV(2),
                In_Ready          => SeamR(2),
                In_Data           => D2,
                In_Last           => SeamL(2),
                In_User           => SeamU(2),
                Out_Valid         => Out_Valid,
                Out_Ready         => Out_Ready,
                Out_Data          => Out_Data,
                Out_Last          => Out_Last,
                Out_User          => Out_User,
                S_AxiLite_ArAddr  => Axi.read_address_channel.araddr(7 downto 0),
                S_AxiLite_ArValid => SIn(1).ArValid,
                S_AxiLite_ArReady => SOut(1).ArReady,
                S_AxiLite_AwAddr  => Axi.write_address_channel.awaddr(7 downto 0),
                S_AxiLite_AwValid => SIn(1).AwValid,
                S_AxiLite_AwReady => SOut(1).AwReady,
                S_AxiLite_WData   => Axi.write_data_channel.wdata,
                S_AxiLite_WStrb   => Axi.write_data_channel.wstrb,
                S_AxiLite_WValid  => SIn(1).WValid,
                S_AxiLite_WReady  => SOut(1).WReady,
                S_AxiLite_BResp   => SOut(1).BResp,
                S_AxiLite_BValid  => SOut(1).BValid,
                S_AxiLite_BReady  => SIn(1).BReady,
                S_AxiLite_RData   => SOut(1).RData,
                S_AxiLite_RResp   => SOut(1).RResp,
                S_AxiLite_RValid  => SOut(1).RValid,
                S_AxiLite_RReady  => SIn(1).RReady,
                Err_Framing       => Pulses(3 * Kinds_c + KFraming_c),
                Err_Config        => Pulses(3 * Kinds_c + KConfig_c),
                Stat_ImageOpen    => Opened(3)
            );

        Ready(0 to 3) <= In_Ready & SeamR(0 to 2);
        Valid(0 to 3) <= SeamV(0 to 2) & Out_Valid;

        -- ECC monitor channels (no isp_replace)
        MonSec <= Pulses(0 * Kinds_c + KSec_c) & Pulses(1 * Kinds_c + KSec_c) & "00";
        MonDed <= Pulses(0 * Kinds_c + KDed_c) & Pulses(1 * Kinds_c + KDed_c) & "00";
    end generate;

    -----------------------------------------------------------------------------------------------
    -- AXI4-Lite decoder: address bits 15 to 12 select the slot; the slot of a write or a read is
    -- kept from its address phase to its response
    -----------------------------------------------------------------------------------------------
    p_slot : process (all) is
    begin
        WSel <= WSelR;
        RSel <= RSelR;
        if Axi.write_address_channel.awvalid = '1' then
            WSel <= to_integer(unsigned(Axi.write_address_channel.awaddr(15 downto 12)));
        end if;
        if Axi.read_address_channel.arvalid = '1' then
            RSel <= to_integer(unsigned(Axi.read_address_channel.araddr(15 downto 12)));
        end if;
    end process;

    p_sel : process (Clk) is
    begin
        if rising_edge(Clk) then
            if Axi.write_address_channel.awvalid = '1' then
                WSelR <= WSel;
            end if;
            if Axi.read_address_channel.arvalid = '1' then
                RSelR <= RSel;
            end if;
        end if;
    end process;

    g_slots : for s in 0 to Slots_c - 1 generate
        SIn(s).AwValid <= Axi.write_address_channel.awvalid when WSel = s else '0';
        SIn(s).WValid  <= Axi.write_data_channel.wvalid when WSel = s else '0';
        SIn(s).BReady  <= Axi.write_response_channel.bready when WSel = s else '0';
        SIn(s).ArValid <= Axi.read_address_channel.arvalid when RSel = s else '0';
        SIn(s).RReady  <= Axi.read_data_channel.rready when RSel = s else '0';
    end generate;

    p_decode : process (all) is
        variable W_v : SlvOut_t;
        variable R_v : SlvOut_t;
    begin
        W_v := SlvOutIdle_c;
        R_v := SlvOutIdle_c;
        if WSel < Slots_c then
            W_v := SOut(WSel);
        end if;
        if RSel < Slots_c then
            R_v := SOut(RSel);
        end if;
        Axi.write_address_channel.awready <= W_v.AwReady;
        Axi.write_data_channel.wready     <= W_v.WReady;
        Axi.write_response_channel.bvalid <= W_v.BValid;
        Axi.write_response_channel.bresp  <= W_v.BResp;
        Axi.read_address_channel.arready  <= R_v.ArReady;
        Axi.read_data_channel.rvalid      <= R_v.RValid;
        Axi.read_data_channel.rresp       <= R_v.RResp;
        Axi.read_data_channel.rdata       <= R_v.RData;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Injection scripts, scrubber gate, module reset script
    -----------------------------------------------------------------------------------------------
    i_inject_rpl : entity work.isp_tb_inject
        generic map (
            InjFile_g      => InjRplFile_g,
            FlipWidth_g    => RplFlipW_c,
            ScrubDefault_g => scrubStart
        )
        port map (
            Clk            => Clk,
            Marker         => Marker,
            Ack            => AckRpl,
            ErrInj_BitFlip => RplFlip,
            ErrInj_Valid   => RplInj,
            Scrub_Enable   => ScrubReq
        );

    i_inject_flt : entity work.isp_tb_inject
        generic map (
            InjFile_g   => InjFltFile_g,
            FlipWidth_g => FltFlipW_c
        )
        port map (
            Clk            => Clk,
            Marker         => Marker,
            Ack            => AckFlt,
            ErrInj_BitFlip => FltFlip,
            ErrInj_Valid   => FltInj,
            Scrub_Enable   => FltScrub
        );

    i_inject_bin : entity work.isp_tb_inject
        generic map (
            InjFile_g   => InjBinFile_g,
            FlipWidth_g => BinFlipW_c
        )
        port map (
            Clk            => Clk,
            Marker         => Marker,
            Ack            => AckBin,
            ErrInj_BitFlip => BinFlip,
            ErrInj_Valid   => BinInj,
            Scrub_Enable   => BinScrub
        );

    -- The scrubber of isp_replace is switched off at the end of a pass, so that the word with a double error is
    -- read a whole number of times (verification plan of isp_replace, section 5)
    p_scrub_gate : process (Clk) is
    begin
        if rising_edge(Clk) then
            if ScrubReq = '1' then
                ScrubOn <= '1';
            elsif PassDn = '1' or InitRst = '1' then
                ScrubOn <= '0';
            end if;
        end if;
    end process;

    Scrub_Ena <= ScrubReq or ScrubOn;

    -- Module reset script: lines "marker position cycles"; the reset of one module at its marker
    p_modrst : process is
        variable L_v   : line;
        variable W_v   : string(1 to WordMax_c);
        variable Len_v : natural;
        variable M_v   : natural;
        variable P_v   : natural;
        variable N_v   : natural;

        file F_v : text;
    begin
        file_open(F_v, ModRstFile_g, read_mode);

        while not endfile(F_v) loop
            readline(F_v, L_v);
            readWord(L_v, W_v, Len_v);
            next when Len_v = 0;
            M_v := decToInt(W_v(1 to Len_v));
            readWord(L_v, W_v, Len_v);
            P_v := decToInt(W_v(1 to Len_v));
            readWord(L_v, W_v, Len_v);
            N_v := decToInt(W_v(1 to Len_v));
            if Marker /= M_v then
                wait until Marker = M_v;
            end if;
            wait until rising_edge(Clk);
            ModReq(P_v) <= '1';

            for i in 1 to N_v loop
                wait until rising_edge(Clk);
            end loop;

            ModReq(P_v) <= '0';
            AckRst      <= M_v;
        end loop;

        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- ECC monitor of the chain (user guide 5, step 4)
    -----------------------------------------------------------------------------------------------
    i_ecc_monitor : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g => 4
        )
        port map (
            Clk        => Clk,
            Rst        => InitRst,
            In_EccSec  => MonSec,
            In_EccDed  => MonDed,
            Rd_Channel => MonRdCh,
            Rd_Ena     => MonRdEna,
            Rd_SecCnt  => MonSecCnt,
            Rd_DedCnt  => MonDedCnt,
            Rd_Valid   => MonRdVld
        );

    -----------------------------------------------------------------------------------------------
    -- Sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Exp_v  : natural;
        variable Name_v : line;

        -- Number of pulses of kind K of position P counted by the testbench
        impure function count (p : natural; k : natural) return natural is
        begin
            return Counts(p * Kinds_c + k);
        end function;

        procedure checkMonitor (ch : natural; sec : natural; ded : natural; name : string) is
        begin
            MonRdCh  <= std_logic_vector(to_unsigned(ch, 2));
            MonRdEna <= '1';
            wait until rising_edge(Clk);
            MonRdEna <= '0';
            wait until rising_edge(Clk) and MonRdVld = '1';
            check_value(to_integer(unsigned(MonSecCnt)), sec, ERROR, "ECC monitor channel " & name & ": SEC count");
            check_value(to_integer(unsigned(MonDedCnt)), ded, ERROR, "ECC monitor channel " & name & ": DED count");
        end procedure;

        constant Names_c : string := "Err_Framing     Err_Config      Stat_EccSec     Stat_EccDed     " &
                                     "Stat_Unreplaced Scrub_EccSec    Scrub_EccDed    Scrub_Overrun   ";
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        disable_log_msg(ID_BFM);

        while test_suite loop
            RateTest <= false;
            FifoTest <= false;
            RegsTest <= false;
            if run("test_rate") then
                RateTest <= true;
            elsif run("test_fifo") or run("neg_fifo_depth") or run("neg_fifo_drain") then
                FifoTest <= true;
            elsif run("test_registers") then
                RegsTest <= true;
            elsif run("test_static") or run("test_input_stream") or run("test_ecc") or
                  run("test_reset") or run("neg_seam_dimension") or run("neg_seam_beat") or
                  run("neg_pulse_count") then
                null;
            end if;

            -- A negative test passes only when its provocation causes exactly the expected errors
            if ExpErrors_g > 0 then
                set_alert_stop_limit(ERROR, 0);
                increment_expected_alerts(ERROR, ExpErrors_g);
            end if;

            InitRst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            InitRst <= '0';

            ispRegsRun(RegsFile_g, ClkPeriod_c, Marker, AckRegs, Clk, Axi);

            wait until SrcDone and SinkDone;

            -- The last pass of the scrubber ends before the counts are checked
            if ScrubOn = '1' and ScrubReq = '0' then
                wait until ScrubOn = '0';
            end if;

            for i in 1 to 4 * (Width_g + 10) loop
                wait until rising_edge(Clk);
            end loop;

            -- The pulses of every module equal the composed model (CHN-FN-03, CHN-IF-02)
            for p in 0 to Stages_c - 1 loop

                for k in 0 to Kinds_c - 1 loop

                    if k = KScrubDed_c and Typical_c and p = 0 then
                        Exp_v := ScrubDedWords_g * PassDone;
                    else
                        Exp_v := Exp_c(p * Kinds_c + k);
                    end if;
                    check_value(count(p, k), Exp_v, ERROR, "position " & integer'image(p) & ": number of " &
                                Names_c(16 * k + 1 to 16 * k + 16) & " pulses");
                end loop;

            end loop;

            if Typical_c then
                check_value(PassDone > 0, ERROR, "isp_replace: no Scrub_PassDone pulse");
                checkMonitor(0, count(0, KSec_c), count(0, KDed_c), "isp_replace");
                checkMonitor(1, count(0, KScrubSec_c), count(0, KScrubDed_c), "isp_replace scrubber");
                checkMonitor(2, count(3, KSec_c), count(3, KDed_c), "isp_filter2d");
                checkMonitor(3, count(4, KSec_c), count(4, KDed_c), "isp_bin");
            else
                checkMonitor(2, count(1, KSec_c), count(1, KDed_c), "isp_filter2d");
                checkMonitor(3, count(0, KSec_c), count(0, KDed_c), "isp_bin");
            end if;

        end loop;

        ispTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Pulses of every position; metavalues of the control and status outputs and of the output
    -----------------------------------------------------------------------------------------------
    p_monitor : process (Clk) is
        variable Started_v : boolean   := false;
        variable RstPrev_v : std_logic := '0';
        variable Status_v  : std_logic_vector(0 to Kinds_c + 2);
    begin
        if rising_edge(Clk) then
            Cycle <= Cycle + 1;
            if Started_v then

                for p in 0 to Stages_c - 1 loop

                    Status_v := Ready(p) & Valid(p) & Opened(p) & Pulses(p * Kinds_c to p * Kinds_c + Kinds_c - 1);
                    if is_x(Status_v) then
                        error("metavalue on a control or status output of position " & integer'image(p) &
                              " (In_Ready, Out_Valid, Stat_ImageOpen, the pulses): " & to_string(Status_v));
                    end if;

                    for k in 0 to Kinds_c - 1 loop

                        if Pulses(p * Kinds_c + k) = '1' then
                            Counts(p * Kinds_c + k) <= Counts(p * Kinds_c + k) + 1;
                        end if;

                    end loop;

                end loop;

                if Out_Valid = '1' and is_x(Out_Data) then
                    error("metavalue in an output pixel of the chain");
                end if;
                if PassDn = '1' then
                    PassDone <= PassDone + 1;
                end if;
            end if;
            if RstPrev_v = '1' and Rst = '0' then
                Started_v := true;
            end if;
            RstPrev_v := Rst;
            -- Beats behind isp_crop (neg_seam_beat)
            if Typical_c and SeamV(2) = '1' and SeamR(2) = '1' then
                NegCount <= NegCount + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Timing of test_rate (verification plan, sections 5.1 and 5.2): images back to back from the
    -- reset on, no gaps and no stalls
    -----------------------------------------------------------------------------------------------
    p_rate : process (Clk) is
        constant AccDepth_c : positive := 8192;

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
        variable HeldLo_v   : natural := natural'high;
        variable HeldHi_v   : natural := 0;
        variable WaitLo_v   : natural := natural'high;
        variable WaitHi_v   : natural := 0;
        variable ImgStart_v : integer := -1;
        variable Image_v    : natural := 0;
        variable Line_v     : natural := 0;
        variable Periods_v  : natural := 0;
        variable PerLo_v    : natural := natural'high;
        variable PerHi_v    : natural := 0;
        variable Pix_v      : natural;
        variable Exp_v      : natural;

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
                Pix_v                       := InN_v mod (Width_g * Height_g);
                if Marker = 1 and Pix_v mod Width_g = 0 then
                    Line_v := Pix_v / Width_g;
                    if Pix_v = 0 then
                        -- Image start: the interval from the image start before
                        if ImgStart_v >= 0 then
                            Exp_v     := Per_g when Periods_v > 0 else PerFirst_g;
                            check_value(Cycle - ImgStart_v, Exp_v, ERROR,
                                        "test_rate: interval between the image starts " & integer'image(Image_v - 1) &
                                        " and " & integer'image(Image_v) & " (CHN-PF-01)");
                            PerLo_v   := minimum(PerLo_v, Cycle - ImgStart_v);
                            PerHi_v   := maximum(PerHi_v, Cycle - ImgStart_v);
                            Periods_v := Periods_v + 1;
                        end if;
                        ImgStart_v := Cycle;
                        Image_v    := Image_v + 1;
                    end if;
                    -- First pixel of a line: the hold cycles since the first pixel of the line before (the last line
                    -- of the image before for line 0)
                    if InN_v > 0 then
                        if Line_v = 1 and Image_v = 1 then
                            check_value(Held_v, HoldFirst_g, ERROR, "test_rate: hold cycles between the first " &
                                        "pixels of lines 0 and 1 of the first image (CHN-PF-01)");
                        elsif Line_v = 1 then
                            check_value(Held_v, HoldWait_g, ERROR, "test_rate: hold cycles between the first pixels " &
                                        "of lines 0 and 1 of image " & integer'image(Image_v - 1) & " (CHN-PF-01)");
                            WaitLo_v := minimum(WaitLo_v, Held_v);
                            WaitHi_v := maximum(WaitHi_v, Held_v);
                        else
                            check_value(Held_v, HoldLine_g, ERROR, "test_rate: hold cycles before the first pixel " &
                                        "of line " & integer'image(Line_v) & " of image " &
                                        integer'image(Image_v - 1) & " (CHN-PF-01)");
                            HeldLo_v := minimum(HeldLo_v, Held_v);
                            HeldHi_v := maximum(HeldHi_v, Held_v);
                        end if;
                    end if;
                    Held_v := 0;
                end if;
                InN_v := InN_v + 1;
            end if;

            -- Every output pixel: the input beat of the chain that completed it, from the timing file of the
            -- composed model (CHN-PF-01, verification plan section 5.2)
            if Out_Valid = '1' and Out_Ready = '1' then
                readline(F_v, L_v);
                readWord(L_v, W_v, Len_v);
                Src_v := decToInt(W_v(1 to Len_v));
                if Marker = 1 and Src_v >= 0 then
                    Lat_v   := Cycle - Acc_v(Src_v mod AccDepth_c);
                    check_value(Lat_v >= LatMin_g and Lat_v <= LatMax_g, ERROR,
                                "test_rate: latency " & integer'image(Lat_v) & " of output pixel " &
                                integer'image(OutN_v) & ", design " & integer'image(LatMin_g) & " to " &
                                integer'image(LatMax_g) & " (CHN-PF-01)");
                    LatLo_v := minimum(LatLo_v, Lat_v);
                    LatHi_v := maximum(LatHi_v, Lat_v);
                end if;
                OutN_v := OutN_v + 1;
            end if;

            if Marker = 2 and Periods_v > 0 then
                log(ID_SEQUENCER, "test_rate: latency " & integer'image(LatLo_v) & " to " & integer'image(LatHi_v) &
                    " cycles; hold cycles per line " & integer'image(HeldLo_v) & " to " & integer'image(HeldHi_v) &
                    ", between lines 0 and 1 " & integer'image(WaitLo_v) & " to " & integer'image(WaitHi_v) &
                    "; " & integer'image(Periods_v) & " image intervals of " & integer'image(PerLo_v) & " to " &
                    integer'image(PerHi_v) & " cycles");
                Periods_v := 0;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Times of the register script in test_registers (verification plan, section 5.4): the cycles
    -- from the last image start at the chain input to the start and to the end of every marker
    -----------------------------------------------------------------------------------------------
    p_regs_time : process (Clk) is
        variable InN_v      : natural := 0;
        variable Start_v    : natural := 0;
        variable MarkPrev_v : natural := 0;
        variable AckPrev_v  : natural := 0;
    begin
        if rising_edge(Clk) and RegsTest then
            if In_Valid = '1' and In_Ready = '1' then
                if InN_v mod (Width_g * Height_g) = 0 then
                    Start_v := Cycle;
                end if;
                InN_v := InN_v + 1;
            end if;
            if Marker /= MarkPrev_v and Marker >= 100 then
                log(ID_SEQUENCER, "test_registers: marker " & integer'image(Marker) & " set " &
                    integer'image(Cycle - Start_v) & " cycles after the last image start at the chain input");
            end if;
            if AckRegs /= AckPrev_v then
                log(ID_SEQUENCER, "test_registers: register accesses of marker " & integer'image(AckRegs) &
                    " done " & integer'image(Cycle - Start_v) &
                    " cycles after the last image start at the chain input");
            end if;
            MarkPrev_v := Marker;
            AckPrev_v  := AckRegs;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- FIFO in front of the chain (test_fifo): never full while the source sends, largest level
    -----------------------------------------------------------------------------------------------
    p_fifo : process (Clk) is
        variable Max_v   : natural := 0;
        variable Held_v  : natural := 0;
        variable Done_v  : boolean := false;
        variable SrcN_v  : natural := 0;
        variable Carry_v : natural := 0;
        variable RdN_v   : natural := 0;
    begin
        if rising_edge(Clk) then
            if FifoTest and not Done_v then
                if Src_Valid = '1' and Src_Ready = '0' then
                    Held_v := Held_v + 1;
                end if;
                -- The image blanking drains the FIFO: when the first pixel of a further image is written, every
                -- pixel written before it has been read (a read in the same cycle counts)
                if In_Valid = '1' and In_Ready = '1' then
                    RdN_v := RdN_v + 1;
                end if;
                if Src_Valid = '1' and Src_Ready = '1' then
                    if SrcN_v > 0 and SrcN_v mod (Width_g * Height_g) = 0 and SrcN_v /= RdN_v then
                        Carry_v := Carry_v + 1;
                        log(ID_SEQUENCER, "test_fifo: " & integer'image(SrcN_v - RdN_v) & " pixels of the image " &
                            "before in the FIFO at the first pixel of image " &
                            integer'image(SrcN_v / (Width_g * Height_g)));
                    end if;
                    SrcN_v := SrcN_v + 1;
                end if;
                Max_v := maximum(Max_v, FifoLevel);
                if SrcDone and SinkDone then
                    check_value(Held_v, 0, ERROR, "test_fifo: cycles in which the FIFO in front of the chain held " &
                                "the source (CHN-PF-02)");
                    check_value(Max_v, FifoLevel_g, ERROR, "test_fifo: largest In_Level of the FIFO (CHN-PF-02)");
                    check_value(Carry_v, 0, ERROR, "test_fifo: images that found pixels of the image before in the " &
                                "FIFO (CHN-PF-02)");
                    log(ID_SEQUENCER, "test_fifo: largest In_Level " & integer'image(Max_v) & " of " &
                        integer'image(FifoDepth_g) & " entries, " & integer'image(Held_v) & " cycles held, " &
                        integer'image(Carry_v) & " images after a carry-over");
                    Done_v := true;
                end if;
            end if;
        end if;
    end process;

end architecture;
