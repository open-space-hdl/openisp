---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Replacement of the non-operational pixels of an image: a defect map of one bit per pixel, in an
-- ECC-protected and scrubbed RAM that the software writes through an AXI4-Lite slave, marks them;
-- every marked pixel is replaced by the interpolation between the nearest operational pixels within
-- MaxGap_g to its left and right in the same line, or by the one found, and stays unchanged when
-- there is none (Stat_Unreplaced). The module is built from isp_frame_sync (RP-1), the map lookup
-- (RP-2), an isp_window of one line with the pixels and their flags (RP-3), the interpolation (RP-4)
-- and the registers (RP-5).
--
-- Documentation: hdl/isp_replace/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;
    use work.isp_replace_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_replace is
    generic (
        -- Dimensions of the image (W, H) and bits per pixel
        ImageWidth_g   : positive;
        ImageHeight_g  : positive;
        PixelBits_g    : positive;
        -- G: the largest distance to an operational pixel that a replacement uses
        MaxGap_g       : natural  := 2;
        -- RAM of the defect map (Open Logic olo_ft_ram_sdp_scrub)
        RamRdLatency_g : positive := 1;
        EccPipeline_g  : natural  := 1;
        RamStyle_g     : string   := "auto";
        ClkFreqHz_g    : real     := 150.0e6;
        ScrubPeriod_g  : real     := 0.0
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- Input pixel stream
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        -- Output pixel stream
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(PixelBits_g - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        -- AXI4-Lite slave of the registers (inactive when left open)
        S_AxiLite_ArAddr  : in    std_logic_vector(7 downto 0)                        := (others => '0');
        S_AxiLite_ArValid : in    std_logic                                           := '0';
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(7 downto 0)                        := (others => '0');
        S_AxiLite_AwValid : in    std_logic                                           := '0';
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0)                       := (others => '0');
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0)                        := (others => '0');
        S_AxiLite_WValid  : in    std_logic                                           := '0';
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic                                           := '0';
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic                                           := '0';
        -- Status
        Err_Framing       : out   std_logic;
        Stat_ImageOpen    : out   std_logic;
        Stat_Unreplaced   : out   std_logic;
        Stat_EccSec       : out   std_logic;
        Stat_EccDed       : out   std_logic;
        -- Error injection into the next write of the defect map (codeword of a 32-bit word)
        ErrInj_BitFlip    : in    std_logic_vector(eccCodewordWidth(32) - 1 downto 0) := (others => '0');
        ErrInj_Valid      : in    std_logic                                           := '0';
        -- Scrubber of the defect map
        Scrub_Enable      : in    std_logic                                           := '1';
        Scrub_EccSec      : out   std_logic;
        Scrub_EccDed      : out   std_logic;
        Scrub_PassDone    : out   std_logic;
        Scrub_Overrun     : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_replace is

    -- G, limited to its range so that a generic out of range reaches the check that names it
    constant G_c     : positive := minimum(maximum(MaxGap_g, 1), 7);
    -- Reach of the search and of the window: G pixels on each side of the pixel (RPL-FN-07)
    constant Reach_c : positive := G_c;
    constant WinX_c  : positive := 2 * Reach_c + 1;
    constant W_c     : positive := maximum(ImageWidth_g, WinX_c);
    constant PB_c    : positive := PixelBits_g;
    -- Element of the window: the operational flag (bit PB_c) beside the pixel
    constant EB_c    : positive := PB_c + 1;

    -- Defect map: Wl words per line, H x Wl words (specification, section 1.1)
    constant Wl_c    : positive := (W_c + 31) / 32;
    constant Words_c : positive := ImageHeight_g * Wl_c;
    constant Depth_c : positive := maximum(2, Words_c);

    -- The scrub period: 0.0 (free running) or 0.001 to 1073741.823 s, the clock 1000.0 to 2.14748e11 Hz for a paced
    -- scrubber. The pacer of Open Logic divides the clock to a tick of 1 kHz with a ratio of at most 214748000
    -- (olo_base_strobe_gen) and counts the period in whole milliseconds, at most 2^30 - 1 (olo_base_strobe_div: the
    -- log2ceil of a larger ratio overflows). A value out of range reaches the scrubber as free running, so that the
    -- elaboration stops at the configuration checks, which name the generics
    constant PeriodOk_c : boolean  := ScrubPeriod_g = 0.0 or (ScrubPeriod_g >= 0.001 and ScrubPeriod_g <= 1073741.823);
    constant ClkOk_c    : boolean  := ScrubPeriod_g <= 0.0 or (ClkFreqHz_g >= 1000.0 and ClkFreqHz_g <= 2.14748e11);
    constant ScrubPer_c : real     := choose(PeriodOk_c and ClkOk_c, ScrubPeriod_g, 0.0);
    constant AW_c       : positive := log2ceil(Depth_c);
    -- Fields of IMAGE
    constant WidthM1_c  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned((W_c - 1) mod 65536, 16));
    constant HeightM1_c : std_logic_vector(15 downto 0) :=
        std_logic_vector(to_unsigned((ImageHeight_g - 1) mod 65536, 16));

    -- Division by d = 2 to 14 as a multiplication with ceil(2^K / d) (architecture, section 6)
    constant K_c  : positive := PB_c + 8;
    constant NW_c : positive := PB_c + 4;

    type Recip_t is array (0 to 15) of unsigned(K_c - 1 downto 0);

    function recipTable return Recip_t is
        variable T_v   : Recip_t := (others => (others => '0'));
        variable One_v : unsigned(K_c downto 0);
    begin
        One_v      := (others => '0');
        One_v(K_c) := '1';

        for d in 2 to 15 loop
            T_v(d) := resize((One_v + d - 1) / d, K_c);
        end loop;

        return T_v;
    end function;

    constant Recip_c : Recip_t := recipTable;

    -- Queue of the map lookup: the word in use and the two words after it; bit 32 SEC, bit 33 DED
    type Queue_t is array (0 to 2) of std_logic_vector(33 downto 0);

    type LkState_t is (Run_s, Start_s);

    type TwoProcess_r is record
        -- RP-2 Map lookup
        LkState  : LkState_t;
        Queue    : Queue_t;
        QCnt     : natural range 0 to 3;
        InFlight : natural range 0 to 3;
        Discard  : natural range 0 to 7;
        RdNext   : natural range 0 to Words_c;
        LkValid  : std_logic;
        LkData   : std_logic_vector(EB_c - 1 downto 0);
        LkLast   : std_logic;
        LkUser   : std_logic_vector(1 downto 0);
        EccSec   : std_logic;
        EccDed   : std_logic;
        -- RP-4 Interpolation: stage 1 search, stage 2 numerator, stage 3 quotient, stage 4 output
        V1       : std_logic;
        V2       : std_logic;
        V3       : std_logic;
        V4       : std_logic;
        Self1    : std_logic_vector(PB_c - 1 downto 0);
        Self2    : std_logic_vector(PB_c - 1 downto 0);
        Self3    : std_logic_vector(PB_c - 1 downto 0);
        Op1      : std_logic;
        Op2      : std_logic;
        Op3      : std_logic;
        L1       : unsigned(PB_c - 1 downto 0);
        L2       : unsigned(PB_c - 1 downto 0);
        L3       : unsigned(PB_c - 1 downto 0);
        R1       : unsigned(PB_c - 1 downto 0);
        R2       : unsigned(PB_c - 1 downto 0);
        R3       : unsigned(PB_c - 1 downto 0);
        Dl1      : natural range 0 to 7;
        Dl2      : natural range 0 to 7;
        Dl3      : natural range 0 to 7;
        Dr1      : natural range 0 to 7;
        Dr2      : natural range 0 to 7;
        Dr3      : natural range 0 to 7;
        N2       : unsigned(NW_c - 1 downto 0);
        D2       : natural range 0 to 15;
        Q3       : unsigned(PB_c - 1 downto 0);
        Last1    : std_logic;
        Last2    : std_logic;
        Last3    : std_logic;
        Last4    : std_logic;
        User1    : std_logic_vector(1 downto 0);
        User2    : std_logic_vector(1 downto 0);
        User3    : std_logic_vector(1 downto 0);
        User4    : std_logic_vector(1 downto 0);
        Out4     : std_logic_vector(PB_c - 1 downto 0);
        Unr4     : std_logic;
        Unrepl   : std_logic;
        -- RP-5 Registers
        MapAddr  : unsigned(31 downto 0);
        Busy     : std_logic;
        ClrAddr  : natural range 0 to Words_c - 1;
        FlagFrm  : std_logic;
        FlagUnr  : std_logic;
        FlagSec  : std_logic;
        FlagDed  : std_logic;
        RdValid  : std_logic;
        RdData   : std_logic_vector(31 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- RP-1 Frame sync
    signal Fs_Valid   : std_logic;
    signal Fs_Ready   : std_logic;
    signal Fs_Data    : std_logic_vector(PB_c - 1 downto 0);
    signal Fs_Last    : std_logic;
    signal Fs_User    : std_logic_vector(1 downto 0);
    signal Fs_PosX    : std_logic_vector(ispPosWidth(W_c) - 1 downto 0);
    signal Fs_PosY    : std_logic_vector(ispPosWidth(ImageHeight_g) - 1 downto 0);
    signal Fs_Framing : std_logic;
    signal Fs_Open    : std_logic;

    -- RP-3 Window
    signal Win_InReady  : std_logic;
    signal Win_OutValid : std_logic;
    signal Win_OutReady : std_logic;
    signal Win_OutData  : std_logic_vector(WinX_c * EB_c - 1 downto 0);
    signal Win_OutLast  : std_logic;
    signal Win_OutUser  : std_logic_vector(1 downto 0);
    signal Win_Framing  : std_logic;

    -- RAM of the defect map
    signal Ram_WrEna   : std_logic;
    signal Ram_WrAddr  : std_logic_vector(AW_c - 1 downto 0);
    signal Ram_WrData  : std_logic_vector(31 downto 0);
    signal Ram_RdEna   : std_logic;
    signal Ram_RdAddr  : std_logic_vector(AW_c - 1 downto 0);
    signal Ram_RdData  : std_logic_vector(31 downto 0);
    signal Ram_RdValid : std_logic;
    signal Ram_RdSec   : std_logic;
    signal Ram_RdDed   : std_logic;
    signal Scrub_Sec   : std_logic;
    signal Scrub_Ded   : std_logic;

    -- Register bus of the AXI4-Lite slave
    signal Rb_Addr    : std_logic_vector(7 downto 0);
    signal Rb_Wr      : std_logic;
    signal Rb_ByteEna : std_logic_vector(3 downto 0);
    signal Rb_WrData  : std_logic_vector(31 downto 0);
    signal Rb_Rd      : std_logic;

begin

    -- RPL-CF-01: the generics outside their range stop the elaboration
    assert MaxGap_g >= 1 and MaxGap_g <= 7
        report "isp_replace: MaxGap_g must be 1 to 7"
        severity failure;
    assert ImageWidth_g >= 2 * MaxGap_g + 1 and ImageWidth_g <= 65536
        report "isp_replace: ImageWidth_g must be 2 x MaxGap_g + 1 to 65536"
        severity failure;
    assert ImageHeight_g <= 65536
        report "isp_replace: ImageHeight_g must be 1 to 65536"
        severity failure;
    assert PixelBits_g <= 24
        report "isp_replace: PixelBits_g must be 1 to 24"
        severity failure;
    assert RamRdLatency_g <= 3
        report "isp_replace: RamRdLatency_g must be 1 to 3"
        severity failure;
    assert EccPipeline_g <= 2
        report "isp_replace: EccPipeline_g must be 0 to 2"
        severity failure;
    assert PeriodOk_c
        report "isp_replace: ScrubPeriod_g must be 0.0 or 0.001 to 1073741.823"
        severity failure;
    assert ClkOk_c
        report "isp_replace: ClkFreqHz_g must be 1000.0 to 2.14748e11 with ScrubPeriod_g above 0.0"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- RP-1 Frame sync
    -----------------------------------------------------------------------------------------------
    i_frame_sync : entity work.isp_frame_sync
        generic map (
            ImageWidth_g  => W_c,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => PB_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => In_Valid,
            In_Ready       => In_Ready,
            In_Data        => In_Data,
            In_Last        => In_Last,
            In_User        => In_User,
            Out_Valid      => Fs_Valid,
            Out_Ready      => Fs_Ready,
            Out_Data       => Fs_Data,
            Out_Last       => Fs_Last,
            Out_User       => Fs_User,
            Out_PosX       => Fs_PosX,
            Out_PosY       => Fs_PosY,
            Err_Framing    => Fs_Framing,
            Stat_ImageOpen => Fs_Open
        );

    -----------------------------------------------------------------------------------------------
    -- RP-2 Defect map: written by RP-5 only, read by the lookup, scrubbed in the other cycles
    -----------------------------------------------------------------------------------------------
    i_map : entity olo.olo_ft_ram_sdp_scrub
        generic map (
            Depth_g        => Depth_c,
            Width_g        => 32,
            RamRdLatency_g => minimum(RamRdLatency_g, 3),
            RamStyle_g     => RamStyle_g,
            EccPipeline_g  => minimum(EccPipeline_g, 2),
            ScrubClkHz_g   => ClkFreqHz_g,
            ScrubPeriod_g  => ScrubPer_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Wr_Addr        => Ram_WrAddr,
            Wr_Ena         => Ram_WrEna,
            Wr_Data        => Ram_WrData,
            Rd_Addr        => Ram_RdAddr,
            Rd_Ena         => Ram_RdEna,
            Rd_Data        => Ram_RdData,
            Rd_Valid       => Ram_RdValid,
            Rd_EccSec      => Ram_RdSec,
            Rd_EccDed      => Ram_RdDed,
            ErrInj_BitFlip => ErrInj_BitFlip,
            ErrInj_Valid   => ErrInj_Valid,
            Scrub_Enable   => Scrub_Enable,
            Scrub_EccSec   => Scrub_Sec,
            Scrub_EccDed   => Scrub_Ded,
            Scrub_PassDone => Scrub_PassDone,
            Scrub_Overrun  => Scrub_Overrun
        );

    Scrub_EccSec <= Scrub_Sec;
    Scrub_EccDed <= Scrub_Ded;

    -----------------------------------------------------------------------------------------------
    -- RP-3 Window: one line of 2 x G + 1 elements, the pixel in the middle, border mode zero, so that
    -- a place outside the image holds the flag 0 (not operational)
    -----------------------------------------------------------------------------------------------
    i_window : entity work.isp_window
        generic map (
            ImageWidth_g  => W_c,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => EB_c,
            WinX_g        => WinX_c,
            WinY_g        => 1,
            AnchorX_g     => Reach_c,
            AnchorY_g     => 0,
            BorderMode_g  => "zero"
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => r.LkValid,
            In_Ready       => Win_InReady,
            In_Data        => r.LkData,
            In_Last        => r.LkLast,
            In_User        => r.LkUser,
            Out_Valid      => Win_OutValid,
            Out_Ready      => Win_OutReady,
            Out_Data       => Win_OutData,
            Out_Last       => Win_OutLast,
            Out_User       => Win_OutUser,
            Err_Framing    => Win_Framing,
            Stat_ImageOpen => open,
            Stat_EccSec    => open,
            Stat_EccDed    => open
        );

    -----------------------------------------------------------------------------------------------
    -- RP-5 AXI4-Lite slave
    -----------------------------------------------------------------------------------------------
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 8,
            AxiDataWidth_g => 32
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Rb_Addr           => Rb_Addr,
            Rb_Wr             => Rb_Wr,
            Rb_ByteEna        => Rb_ByteEna,
            Rb_WrData         => Rb_WrData,
            Rb_Rd             => Rb_Rd,
            Rb_RdData         => r.RdData,
            Rb_RdValid        => r.RdValid
        );

    -----------------------------------------------------------------------------------------------
    -- RP-2 Map lookup, RP-4 Interpolation, RP-5 Registers
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        -- Map lookup
        variable X_v       : natural;
        variable Bit_v     : natural range 0 to 31;
        variable Start_v   : boolean;
        variable Take_v    : boolean;
        variable Pop_v     : boolean;
        variable Use_v     : boolean;
        variable Word_v    : std_logic_vector(33 downto 0);
        variable Arr_v     : boolean;
        variable ArrWord_v : std_logic_vector(33 downto 0);
        variable LkAdv_v   : boolean;
        -- Interpolation
        variable Adv_v     : boolean;
        variable Flag_v    : std_logic_vector(WinX_c - 1 downto 0);
        variable Pix_v     : std_logic_vector(PB_c - 1 downto 0);
        variable Dl_v      : natural range 0 to 7;
        variable Dr_v      : natural range 0 to 7;
        variable Prod_v    : unsigned(NW_c + K_c - 1 downto 0);
        -- Registers
        variable Addr_v    : natural;
        variable MapWr_v   : boolean;
        variable ClrFrm_v  : boolean;
        variable ClrUnr_v  : boolean;
        variable ClrSec_v  : boolean;
        variable ClrDed_v  : boolean;
    begin
        v        := r;
        v.EccSec := '0';
        v.EccDed := '0';
        v.Unrepl := '0';

        -------------------------------------------------------------------------------------------
        -- RP-2 Map lookup (architecture, section 5)
        -------------------------------------------------------------------------------------------
        -- A word read from the map joins the queue, unless it belongs to a read-ahead that an image start dropped or
        -- no read is pending; the latter is a defence against an upset of the counter (RPL-FT-02), and it keeps the
        -- counter in its range when the read valid of the RAM rises for zero time in simulation as a read of the
        -- scrubber returns
        Arr_v     := false;
        ArrWord_v := Ram_RdDed & Ram_RdSec & Ram_RdData;
        if Ram_RdValid = '1' then
            if r.Discard > 0 then
                v.Discard := r.Discard - 1;
            elsif r.InFlight > 0 then
                v.InFlight := r.InFlight - 1;
                Arr_v      := true;
            end if;
        end if;

        X_v     := to_integer(unsigned(Fs_PosX));
        Bit_v   := X_v mod 32;
        Start_v := X_v = 0 and to_integer(unsigned(Fs_PosY)) = 0;
        LkAdv_v := r.LkValid = '0' or Win_InReady = '1';
        Take_v  := false;
        Pop_v   := false;
        Use_v   := false;
        Word_v  := r.Queue(0);

        case r.LkState is

            when Run_s =>
                if Fs_Valid = '1' and Start_v then
                    -- Pixel (0, 0): the reads of the image start from word 0 (never across the image start,
                    -- RPL-FN-04); the pixel waits for word 0
                    v.LkState  := Start_s;
                    v.QCnt     := 0;
                    v.RdNext   := 0;
                    v.Discard  := minimum(v.Discard + v.InFlight, 7);
                    v.InFlight := 0;
                    Arr_v      := false;
                elsif Fs_Valid = '1' and LkAdv_v then
                    if Bit_v = 0 then
                        -- The first pixel of a word: the next word comes in use
                        if r.QCnt >= 2 then
                            Take_v := true;
                            Pop_v  := true;
                            Use_v  := true;
                            Word_v := r.Queue(1);
                        elsif r.RdNext = Words_c and r.InFlight = 0 then
                            -- No word can come (only after an upset): the pixel passes as operational until the
                            -- next image start realigns the lookup (RPL-FT-02)
                            Take_v := true;
                            Word_v := (others => '0');
                        end if;
                    elsif r.QCnt >= 1 then
                        Take_v := true;
                    elsif r.RdNext = Words_c and r.InFlight = 0 then
                        Take_v := true;
                        Word_v := (others => '0');
                    end if;
                end if;

            when Start_s =>
                if Fs_Valid = '1' and LkAdv_v and r.QCnt >= 1 then
                    Take_v    := true;
                    Use_v     := true;
                    v.LkState := Run_s;
                end if;

            when others =>
                v.LkState := Run_s;

        end case;

        -- The queue moves on by one word; the flags of the word that comes in use are reported now: only a word that
        -- the image uses reports its errors (RPL-IF-04)
        if Pop_v then
            v.Queue(0) := r.Queue(1);
            v.Queue(1) := r.Queue(2);
            v.QCnt     := r.QCnt - 1;
        end if;
        if Use_v then
            v.EccSec := Word_v(32);
            v.EccDed := Word_v(33);
        end if;
        if Arr_v then
            v.Queue(v.QCnt) := ArrWord_v;
            v.QCnt          := v.QCnt + 1;
        end if;

        -- Read-ahead: the word in use and the two words after it, up to the last word of the image
        Ram_RdEna  <= '0';
        Ram_RdAddr <= std_logic_vector(to_unsigned(v.RdNext mod Depth_c, AW_c));
        if v.QCnt + v.InFlight < 3 and v.RdNext < Words_c then
            Ram_RdEna  <= '1';
            v.RdNext   := v.RdNext + 1;
            v.InFlight := v.InFlight + 1;
        end if;

        -- Output register of the lookup: the pixel with its operational flag (the inverse of its mark)
        Fs_Ready <= '0';
        if LkAdv_v then
            v.LkValid := '0';
        end if;
        if Take_v then
            Fs_Ready  <= '1';
            v.LkValid := '1';
            v.LkData  := (not Word_v(Bit_v)) & Fs_Data;
            v.LkLast  := Fs_Last;
            v.LkUser  := Fs_User;
        end if;

        -------------------------------------------------------------------------------------------
        -- RP-4 Interpolation (architecture, section 6); all stages share one enable
        -------------------------------------------------------------------------------------------
        Adv_v := r.V4 = '0' or Out_Ready = '1';
        if Adv_v then
            Win_OutReady <= '1';
        else
            Win_OutReady <= '0';
        end if;

        -- Stat_Unreplaced pulses when an unreplaced pixel leaves the module, so that a pixel lost by a reset reports
        -- nothing (RPL-IF-04)
        if r.V4 = '1' and r.Unr4 = '1' and Out_Ready = '1' then
            v.Unrepl := '1';
        end if;

        if Adv_v then
            -- Stage 4: output register
            v.V4    := r.V3;
            v.Last4 := r.Last3;
            v.User4 := r.User3;
            v.Unr4  := '0';
            if r.Op3 = '1' then
                v.Out4 := r.Self3;
            elsif r.Dl3 = 0 and r.Dr3 = 0 then
                -- E5: no operational pixel within G on either side
                v.Out4 := r.Self3;
                v.Unr4 := '1';
            elsif r.Dl3 = 0 then
                v.Out4 := std_logic_vector(r.R3);
            elsif r.Dr3 = 0 then
                v.Out4 := std_logic_vector(r.L3);
            else
                v.Out4 := std_logic_vector(r.Q3);
            end if;

            -- Stage 3: Q = floor(N / d) = N x ceil(2^K / d) / 2^K
            Prod_v  := r.N2 * Recip_c(r.D2);
            v.Q3    := resize(shift_right(Prod_v, K_c), PB_c);
            v.V3    := r.V2;
            v.Self3 := r.Self2;
            v.Op3   := r.Op2;
            v.L3    := r.L2;
            v.R3    := r.R2;
            v.Dl3   := r.Dl2;
            v.Dr3   := r.Dr2;
            v.Last3 := r.Last2;
            v.User3 := r.User2;

            -- Stage 2: N = L x dr + R x dl + floor(d / 2), d = dl + dr
            v.N2    := resize(r.L1 * to_unsigned(r.Dr1, 3), NW_c) + resize(r.R1 * to_unsigned(r.Dl1, 3), NW_c) +
                       to_unsigned((r.Dl1 + r.Dr1) / 2, NW_c);
            v.D2    := r.Dl1 + r.Dr1;
            v.V2    := r.V1;
            v.Self2 := r.Self1;
            v.Op2   := r.Op1;
            v.L2    := r.L1;
            v.R2    := r.R1;
            v.Dl2   := r.Dl1;
            v.Dr2   := r.Dr1;
            v.Last2 := r.Last1;
            v.User2 := r.User1;

            -- Stage 1: the nearest operational pixel on each side within G, and the pixels L and R
            for i in 0 to WinX_c - 1 loop
                Flag_v(i) := Win_OutData(i * EB_c + PB_c);
            end loop;

            Dl_v := 0;
            Dr_v := 0;

            for d in Reach_c downto 1 loop
                if Flag_v(Reach_c - d) = '1' then
                    Dl_v := d;
                end if;
                if Flag_v(Reach_c + d) = '1' then
                    Dr_v := d;
                end if;
            end loop;

            v.L1 := (others => '0');
            v.R1 := (others => '0');
            if Dl_v > 0 then
                Pix_v := Win_OutData((Reach_c - Dl_v) * EB_c + PB_c - 1 downto (Reach_c - Dl_v) * EB_c);
                v.L1  := unsigned(Pix_v);
            end if;
            if Dr_v > 0 then
                Pix_v := Win_OutData((Reach_c + Dr_v) * EB_c + PB_c - 1 downto (Reach_c + Dr_v) * EB_c);
                v.R1  := unsigned(Pix_v);
            end if;
            v.Dl1   := Dl_v;
            v.Dr1   := Dr_v;
            v.Self1 := Win_OutData(Reach_c * EB_c + PB_c - 1 downto Reach_c * EB_c);
            v.Op1   := Flag_v(Reach_c);
            v.V1    := Win_OutValid;
            v.Last1 := Win_OutLast;
            v.User1 := Win_OutUser;
        end if;

        -------------------------------------------------------------------------------------------
        -- RP-5 Registers (specification, section 7)
        -------------------------------------------------------------------------------------------
        Ram_WrEna  <= '0';
        Ram_WrAddr <= std_logic_vector(to_unsigned(r.ClrAddr mod Depth_c, AW_c));
        Ram_WrData <= (others => '0');

        -- Clear sequence: one word per cycle, from word 0 to the last word (RPL-RG-04)
        if r.Busy = '1' then
            Ram_WrEna <= '1';
            if r.ClrAddr = Words_c - 1 then
                v.Busy := '0';
            else
                v.ClrAddr := r.ClrAddr + 1;
            end if;
        end if;

        ClrFrm_v := false;
        ClrUnr_v := false;
        ClrSec_v := false;
        ClrDed_v := false;
        Addr_v   := to_integer(unsigned(Rb_Addr));
        if Rb_Wr = '1' then
            if Addr_v = RegCtrl_c then
                if Rb_ByteEna(0) = '1' and Rb_WrData(CtrlClear_c) = '1' and r.Busy = '0' then
                    v.Busy    := '1';
                    v.ClrAddr := 0;
                end if;
            elsif Addr_v = RegStatus_c then
                ClrFrm_v := Rb_ByteEna(1) = '1' and Rb_WrData(StatusErrFraming_c) = '1';
                ClrUnr_v := Rb_ByteEna(1) = '1' and Rb_WrData(StatusUnreplaced_c) = '1';
                ClrSec_v := Rb_ByteEna(2) = '1' and Rb_WrData(StatusEccSec_c) = '1';
                ClrDed_v := Rb_ByteEna(2) = '1' and Rb_WrData(StatusEccDed_c) = '1';
            elsif Addr_v = RegMapAddr_c then

                for b in 0 to 3 loop
                    if Rb_ByteEna(b) = '1' then
                        v.MapAddr(8 * b + 7 downto 8 * b) := unsigned(Rb_WrData(8 * b + 7 downto 8 * b));
                    end if;
                end loop;

            elsif Addr_v = RegMapData_c then
                -- All 32 bits, whatever the strobes; no effect during a clear or outside the map (RPL-ER-04)
                MapWr_v := r.Busy = '0' and r.MapAddr < Words_c;
                if MapWr_v then
                    Ram_WrEna  <= '1';
                    Ram_WrAddr <= std_logic_vector(resize(r.MapAddr, AW_c));
                    Ram_WrData <= Rb_WrData;
                end if;
                if MapWr_v then
                    v.MapAddr := r.MapAddr + 1;
                end if;
            end if;
        end if;

        -- Sticky flags: the event wins over a clear in the same cycle (RPL-RG-02)
        if ClrFrm_v then
            v.FlagFrm := '0';
        end if;
        if ClrUnr_v then
            v.FlagUnr := '0';
        end if;
        if ClrSec_v then
            v.FlagSec := '0';
        end if;
        if ClrDed_v then
            v.FlagDed := '0';
        end if;
        if Fs_Framing = '1' or Win_Framing = '1' then
            v.FlagFrm := '1';
        end if;
        if r.Unrepl = '1' then
            v.FlagUnr := '1';
        end if;
        if r.EccSec = '1' or Scrub_Sec = '1' then
            v.FlagSec := '1';
        end if;
        if r.EccDed = '1' or Scrub_Ded = '1' then
            v.FlagDed := '1';
        end if;

        -- Register reads, answered in the next cycle
        v.RdValid := '0';
        if Rb_Rd = '1' then
            v.RdValid := '1';
            v.RdData  := (others => '0');
            if Addr_v = RegId_c then
                v.RdData := RegMapId_c;
            elsif Addr_v = RegImage_c then
                v.RdData(ImageWidthM1Hi_c downto ImageWidthM1Lo_c)   := WidthM1_c;
                v.RdData(ImageHeightM1Hi_c downto ImageHeightM1Lo_c) := HeightM1_c;
            elsif Addr_v = RegParam_c then
                v.RdData(ParamMaxGapHi_c downto ParamMaxGapLo_c)       := std_logic_vector(to_unsigned(G_c, 4));
                v.RdData(ParamPixelBitsHi_c downto ParamPixelBitsLo_c) := std_logic_vector(to_unsigned(PB_c, 5));
            elsif Addr_v = RegMapLine_c then
                v.RdData(MapLineWordsHi_c downto MapLineWordsLo_c) := std_logic_vector(to_unsigned(Wl_c, 16));
            elsif Addr_v = RegMapWords_c then
                v.RdData := std_logic_vector(to_unsigned(Words_c, 32));
            elsif Addr_v = RegStatus_c then
                v.RdData(StatusImageOpen_c)  := Fs_Open;
                v.RdData(StatusBusy_c)       := r.Busy;
                v.RdData(StatusErrFraming_c) := r.FlagFrm;
                v.RdData(StatusUnreplaced_c) := r.FlagUnr;
                v.RdData(StatusEccSec_c)     := r.FlagSec;
                v.RdData(StatusEccDed_c)     := r.FlagDed;
            elsif Addr_v = RegMapAddr_c then
                v.RdData := std_logic_vector(r.MapAddr);
            end if;
        end if;

        r_next <= v;
    end process;

    Out_Valid       <= r.V4;
    Out_Data        <= r.Out4;
    Out_Last        <= r.Last4;
    Out_User        <= r.User4;
    Err_Framing     <= Fs_Framing or Win_Framing;
    Stat_ImageOpen  <= Fs_Open;
    Stat_Unreplaced <= r.Unrepl;
    Stat_EccSec     <= r.EccSec;
    Stat_EccDed     <= r.EccDed;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.LkState  <= Run_s;
                r.QCnt     <= 0;
                r.InFlight <= 0;
                r.Discard  <= 0;
                r.RdNext   <= Words_c;
                r.LkValid  <= '0';
                r.EccSec   <= '0';
                r.EccDed   <= '0';
                r.V1       <= '0';
                r.V2       <= '0';
                r.V3       <= '0';
                r.V4       <= '0';
                r.Unrepl   <= '0';
                r.MapAddr  <= (others => '0');
                r.Busy     <= '0';
                r.ClrAddr  <= 0;
                r.FlagFrm  <= '0';
                r.FlagUnr  <= '0';
                r.FlagSec  <= '0';
                r.FlagDed  <= '0';
                r.RdValid  <= '0';
            end if;
        end if;
    end process;

end architecture;
