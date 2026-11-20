---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Pixel operation of OpenISP: q = min(max(floor((p + Offset) x Gain / 2^Shift), Low), High) for
-- every pixel of an image of ImageWidth_g x ImageHeight_g pixels. The parameter set comes from the
-- generics or, with Runtime_g, from registers on an AXI4-Lite slave, taken with every image start
-- (CTRL.HOLD keeps the set of the image before) and checked by one parity bit per register; a
-- register with a wrong parity bit makes the image use the generics (Err_Config).
--
-- Documentation: hdl/isp_point/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.isp_pkg.all;
    use work.isp_point_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_point is
    generic (
        -- Dimensions of the image (W, H)
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        -- Bits of the input and the output pixels and of the gain; the largest shift
        InBits_g      : positive;
        OutBits_g     : positive;
        GainBits_g    : positive := 16;
        MaxShift_g    : natural  := InBits_g + GainBits_g;
        -- Parameter set of the generics; with Runtime_g the reset values of the registers. High_g -1 is full scale
        Offset_g      : integer  := 0;
        Gain_g        : natural  := 1;
        Shift_g       : natural  := 0;
        Low_g         : natural  := 0;
        High_g        : integer  := -1;
        Runtime_g     : boolean  := false;
        -- Register stages of the multiplier
        MultStages_g  : positive := 2
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- Input pixel stream
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(InBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        -- Output pixel stream
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(OutBits_g - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        -- AXI4-Lite slave of the registers (inactive when left open)
        S_AxiLite_ArAddr  : in    std_logic_vector(7 downto 0)  := (others => '0');
        S_AxiLite_ArValid : in    std_logic                     := '0';
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(7 downto 0)  := (others => '0');
        S_AxiLite_AwValid : in    std_logic                     := '0';
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0) := (others => '0');
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0)  := (others => '0');
        S_AxiLite_WValid  : in    std_logic                     := '0';
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic                     := '0';
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic                     := '0';
        -- Status
        Err_Framing       : out   std_logic;
        Err_Config        : out   std_logic;
        Stat_ImageOpen    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_point is

    -- Widths: offset (OW), sum (SW), product and shifted value (PW), clamp comparison (CW)
    constant OW_c : positive := minimum(InBits_g + 1, 64);

    -- Bits of the offset in OFFSET_LO and in OFFSET_HI
    constant OffLoBits_c : positive := minimum(OW_c, 32);
    constant OffHiBits_c : natural  := OW_c - OffLoBits_c;
    constant SW_c        : positive := InBits_g + 2;
    constant PW_c        : positive := InBits_g + GainBits_g + 2;
    constant CW_c        : positive := maximum(PW_c, OutBits_g) + 1;

    -- The generics as values of the registers
    constant FullScale_c : unsigned(OutBits_g - 1 downto 0)  := (others => '1');
    constant GenOffset_c : signed(OW_c - 1 downto 0)         := to_signed(Offset_g, OW_c);
    constant GenGain_c   : unsigned(GainBits_g - 1 downto 0) := to_unsigned(Gain_g mod 2 ** GainBits_g, GainBits_g);
    constant GenShift_c  : unsigned(6 downto 0)              := to_unsigned(Shift_g mod 128, 7);

    function genThreshold (value : integer) return unsigned is
    begin
        if value < 0 then
            return FullScale_c;
        end if;
        return to_unsigned(value, OutBits_g);
    end function;

    constant GenLow_c  : unsigned(OutBits_g - 1 downto 0) := genThreshold(Low_g);
    constant GenHigh_c : unsigned(OutBits_g - 1 downto 0) := genThreshold(High_g);

    -- Parameter registers in the order of INJECT.PARITY
    constant ParOffLo_c : natural := 0;
    constant ParOffHi_c : natural := 1;
    constant ParGain_c  : natural := 2;
    constant ParShift_c : natural := 3;
    constant ParLow_c   : natural := 4;
    constant ParHigh_c  : natural := 5;
    constant ParCtrl_c  : natural := 6;

    -- Stages: 1 sum, 2 to 1 + MultStages_g product, 2 + MultStages_g shifted value, 3 + MultStages_g output register
    constant Stages_c : positive := MultStages_g + 3;

    type Product_t is array (1 to MultStages_g) of signed(PW_c - 1 downto 0);
    type Shift_t is array (1 to MultStages_g + 1) of unsigned(6 downto 0);
    type Threshold_t is array (1 to MultStages_g + 2) of unsigned(OutBits_g - 1 downto 0);

    -- Valid (0), Last (1) and the sequence flags (3:2) of every stage
    type Flags_t is array (1 to Stages_c) of std_logic_vector(3 downto 0);

    -- Parity of the offset bits in OFFSET_LO (bits below 32) or in OFFSET_HI (bits from 32)
    function offsetParity (
        offset : signed;
        high   : boolean) return std_logic is
        variable P_v : std_logic := '0';
    begin

        for i in 0 to offset'length - 1 loop
            if (i >= 32) = high then
                P_v := P_v xor offset(offset'low + i);
            end if;
        end loop;

        return P_v;
    end function;

    type TwoProcess_r is record
        -- Parameter registers (PT-4) and their parity bits
        Offset      : signed(OW_c - 1 downto 0);
        Gain        : unsigned(GainBits_g - 1 downto 0);
        Shift       : unsigned(6 downto 0);
        Low         : unsigned(OutBits_g - 1 downto 0);
        High        : unsigned(OutBits_g - 1 downto 0);
        Parity      : std_logic_vector(6 downto 0);
        Hold        : std_logic;
        FlagFraming : std_logic;
        FlagConfig  : std_logic;
        RdValid     : std_logic;
        RdData      : std_logic_vector(31 downto 0);
        -- Working parameter set (PT-2), loaded with pixel (0, 0)
        WOffset     : signed(OW_c - 1 downto 0);
        WGain       : unsigned(GainBits_g - 1 downto 0);
        WShift      : unsigned(6 downto 0);
        WLow        : unsigned(OutBits_g - 1 downto 0);
        WHigh       : unsigned(OutBits_g - 1 downto 0);
        ErrConfig   : std_logic;
        -- Stage 1: sum and the parameters that the pixel carries
        Sum         : signed(SW_c - 1 downto 0);
        SGain       : unsigned(GainBits_g - 1 downto 0);
        -- Stages 2 to 1 + MultStages_g: product; stage 2 + MultStages_g: shifted value
        Prod        : Product_t;
        Shifted     : signed(PW_c - 1 downto 0);
        PShift      : Shift_t;
        PLow        : Threshold_t;
        PHigh       : Threshold_t;
        PFlags      : Flags_t;
        -- Output register (PT-3)
        OutData     : std_logic_vector(OutBits_g - 1 downto 0);
    end record;

    -- Parity bits of the reset values
    constant ParityRst_c : std_logic_vector(6 downto 0) :=
        '0' & (xor GenHigh_c) & (xor GenLow_c) & (xor GenShift_c) & (xor GenGain_c) & offsetParity(GenOffset_c, true) &
        offsetParity(GenOffset_c, false);

    signal r, r_next : TwoProcess_r;

    -- PT-1 Frame sync
    signal FsValid      : std_logic;
    signal FsReady      : std_logic;
    signal FsData       : std_logic_vector(InBits_g - 1 downto 0);
    signal FsLast       : std_logic;
    signal FsUser       : std_logic_vector(1 downto 0);
    signal FsPosX       : std_logic_vector(ispPosWidth(ImageWidth_g) - 1 downto 0);
    signal FsPosY       : std_logic_vector(ispPosWidth(ImageHeight_g) - 1 downto 0);
    signal FsErrFraming : std_logic;
    signal FsImageOpen  : std_logic;

    -- Register bus of the AXI4-Lite slave
    signal Rb_Addr    : std_logic_vector(7 downto 0);
    signal Rb_Wr      : std_logic;
    signal Rb_ByteEna : std_logic_vector(3 downto 0);
    signal Rb_WrData  : std_logic_vector(31 downto 0);
    signal Rb_Rd      : std_logic;

    -- A 32-bit word with the bytes of a write that the strobes select
    function strobed (
        old    : std_logic_vector(31 downto 0);
        data   : std_logic_vector(31 downto 0);
        enable : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable Res_v : std_logic_vector(31 downto 0) := old;
    begin

        for b in 0 to 3 loop
            if enable(b) = '1' then
                Res_v(8 * b + 7 downto 8 * b) := data(8 * b + 7 downto 8 * b);
            end if;
        end loop;

        return Res_v;
    end function;

begin

    -- PNT-CF-01: the generics outside their range stop the elaboration
    assert ImageWidth_g <= 65536
        report "isp_point: ImageWidth_g must be 1 to 65536"
        severity failure;
    assert ImageHeight_g <= 65536
        report "isp_point: ImageHeight_g must be 1 to 65536"
        severity failure;
    assert InBits_g <= 64
        report "isp_point: InBits_g must be 1 to 64"
        severity failure;
    assert OutBits_g <= 32
        report "isp_point: OutBits_g must be 1 to 32"
        severity failure;
    assert GainBits_g <= 18
        report "isp_point: GainBits_g must be 1 to 18"
        severity failure;
    assert MaxShift_g <= InBits_g + GainBits_g + 1
        report "isp_point: MaxShift_g must be 0 to InBits_g + GainBits_g + 1"
        severity failure;
    assert MultStages_g <= 4
        report "isp_point: MultStages_g must be 1 to 4"
        severity failure;
    assert OW_c >= 32 or (Offset_g >= -2 ** (OW_c - 1) and Offset_g <= 2 ** (OW_c - 1) - 1)
        report "isp_point: Offset_g must lie in the range of a signed number of min(InBits_g + 1, 64) bits"
        severity failure;
    assert GainBits_g >= 31 or Gain_g <= 2 ** GainBits_g - 1
        report "isp_point: Gain_g must be 0 to 2^GainBits_g - 1"
        severity failure;
    assert Shift_g <= MaxShift_g
        report "isp_point: Shift_g must be 0 to MaxShift_g"
        severity failure;
    assert OutBits_g >= 31 or Low_g <= 2 ** OutBits_g - 1
        report "isp_point: Low_g must be 0 to 2^OutBits_g - 1"
        severity failure;
    assert High_g >= -1 and (OutBits_g >= 31 or High_g <= 2 ** OutBits_g - 1)
        report "isp_point: High_g must be -1 or 0 to 2^OutBits_g - 1"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- PT-1 Frame sync
    -----------------------------------------------------------------------------------------------
    i_frame_sync : entity work.isp_frame_sync
        generic map (
            ImageWidth_g  => ImageWidth_g,
            ImageHeight_g => ImageHeight_g,
            PixelBits_g   => InBits_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => In_Valid,
            In_Ready       => In_Ready,
            In_Data        => In_Data,
            In_Last        => In_Last,
            In_User        => In_User,
            Out_Valid      => FsValid,
            Out_Ready      => FsReady,
            Out_Data       => FsData,
            Out_Last       => FsLast,
            Out_User       => FsUser,
            Out_PosX       => FsPosX,
            Out_PosY       => FsPosY,
            Err_Framing    => FsErrFraming,
            Stat_ImageOpen => FsImageOpen
        );

    -----------------------------------------------------------------------------------------------
    -- PT-4 AXI4-Lite slave
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
    -- PT-2 Arithmetic, PT-3 Clamp, PT-4 Registers
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Advance_v : boolean;
        variable Start_v   : boolean;
        variable CtrlBad_v : boolean;
        variable Off_v     : signed(OW_c - 1 downto 0);
        variable Gain_v    : unsigned(GainBits_g - 1 downto 0);
        variable Shift_v   : unsigned(6 downto 0);
        variable Low_v     : unsigned(OutBits_g - 1 downto 0);
        variable High_v    : unsigned(OutBits_g - 1 downto 0);
        variable Off64_v   : signed(63 downto 0);
        variable Word_v    : std_logic_vector(31 downto 0);
        variable Clamp_v   : signed(CW_c - 1 downto 0);
        variable ClrFrm_v  : boolean;
        variable ClrCfg_v  : boolean;
    begin
        v           := r;
        v.ErrConfig := '0';

        -- All stages advance together when the output register is empty or its beat transfers
        Advance_v := r.PFlags(Stages_c)(0) = '0' or Out_Ready = '1';
        if Advance_v then
            FsReady <= '1';
        else
            FsReady <= '0';
        end if;

        if Advance_v then
            -- Output register (3 + MultStages_g): min(max(v, Low), High), the lower threshold first
            Clamp_v := resize(r.Shifted, CW_c);
            if Clamp_v < signed(resize(r.PLow(MultStages_g + 2), CW_c)) then
                Clamp_v := signed(resize(r.PLow(MultStages_g + 2), CW_c));
            end if;
            if Clamp_v > signed(resize(r.PHigh(MultStages_g + 2), CW_c)) then
                Clamp_v := signed(resize(r.PHigh(MultStages_g + 2), CW_c));
            end if;
            v.OutData := std_logic_vector(unsigned(Clamp_v(OutBits_g - 1 downto 0)));

            -- Shift stage (2 + MultStages_g): arithmetic shift right, floor
            v.Shifted := shift_right(r.Prod(MultStages_g), to_integer(r.PShift(MultStages_g + 1)));

            -- Product stages
            for k in MultStages_g downto 2 loop
                v.Prod(k) := r.Prod(k - 1);
            end loop;

            v.Prod(1) := resize(r.Sum * signed('0' & r.SGain), PW_c);

            -- Parameters and packet signals travel with the pixel
            for k in Stages_c downto 2 loop
                v.PFlags(k) := r.PFlags(k - 1);
            end loop;

            for k in MultStages_g + 2 downto 2 loop
                v.PLow(k)  := r.PLow(k - 1);
                v.PHigh(k) := r.PHigh(k - 1);
            end loop;

            for k in MultStages_g + 1 downto 2 loop
                v.PShift(k) := r.PShift(k - 1);
            end loop;

            -- Stage 1: the pixel of the frame sync, with the parameter set of its image
            v.PFlags(1)(0) := FsValid;
            if FsValid = '1' then
                Start_v := unsigned(FsPosX) = 0 and unsigned(FsPosY) = 0;
                Off_v   := r.WOffset;
                Gain_v  := r.WGain;
                Shift_v := r.WShift;
                Low_v   := r.WLow;
                High_v  := r.WHigh;
                -- PNT-ER-04: a CTRL with a wrong parity bit counts as HOLD 0 and is reported
                CtrlBad_v := r.Hold /= r.Parity(ParCtrl_c);
                if Runtime_g and Start_v and CtrlBad_v then
                    v.ErrConfig := '1';
                end if;
                if Runtime_g and Start_v and (r.Hold = '0' or CtrlBad_v) then
                    -- PNT-FN-04, PNT-ER-03: the registers with matching parity, otherwise the generics
                    if offsetParity(r.Offset, false) = r.Parity(ParOffLo_c) and
                       offsetParity(r.Offset, true) = r.Parity(ParOffHi_c) and
                       (xor r.Gain) = r.Parity(ParGain_c) and (xor r.Shift) = r.Parity(ParShift_c) and
                       (xor r.Low) = r.Parity(ParLow_c) and (xor r.High) = r.Parity(ParHigh_c) then
                        Off_v   := r.Offset;
                        Gain_v  := r.Gain;
                        Shift_v := r.Shift;
                        Low_v   := r.Low;
                        High_v  := r.High;
                    else
                        Off_v       := GenOffset_c;
                        Gain_v      := GenGain_c;
                        Shift_v     := GenShift_c;
                        Low_v       := GenLow_c;
                        High_v      := GenHigh_c;
                        v.ErrConfig := '1';
                    end if;
                    -- PNT-FN-05: a shift above MaxShift_g is taken as MaxShift_g
                    if Shift_v > MaxShift_g then
                        Shift_v := to_unsigned(MaxShift_g, 7);
                    end if;
                    v.WOffset := Off_v;
                    v.WGain   := Gain_v;
                    v.WShift  := Shift_v;
                    v.WLow    := Low_v;
                    v.WHigh   := High_v;
                end if;
                v.Sum                   := resize(signed('0' & FsData), SW_c) + resize(Off_v, SW_c);
                v.SGain                 := Gain_v;
                v.PShift(1)             := Shift_v;
                v.PLow(1)               := Low_v;
                v.PHigh(1)              := High_v;
                v.PFlags(1)(1)          := FsLast;
                v.PFlags(1)(3 downto 2) := FsUser;
            end if;
        end if;

        -- PT-4: register writes
        ClrFrm_v := false;
        ClrCfg_v := false;
        if Rb_Wr = '1' then
            Off64_v := resize(r.Offset, 64);

            case to_integer(unsigned(Rb_Addr)) is

                when RegCtrl_c =>
                    if Rb_ByteEna(0) = '1' then
                        v.Hold              := Rb_WrData(CtrlHold_c);
                        v.Parity(ParCtrl_c) := Rb_WrData(CtrlHold_c);
                    end if;

                when RegStatus_c =>
                    if Rb_ByteEna(1) = '1' then
                        ClrFrm_v := Rb_WrData(StatusErrFraming_c) = '1';
                        ClrCfg_v := Rb_WrData(StatusErrConfig_c) = '1';
                    end if;

                when RegInject_c =>
                    if Runtime_g and Rb_ByteEna(0) = '1' then
                        v.Parity := r.Parity xor Rb_WrData(InjectParityHi_c downto InjectParityLo_c);
                    end if;

                when RegOffsetLo_c =>
                    if Runtime_g then
                        -- The parity bit of every parameter register: a write of every byte with bits of the register
                        -- sets it for the written value, a write that keeps such a byte keeps a mismatch (PNT-RG-03)
                        v.Parity(ParOffLo_c) := ispWriteParity(std_logic_vector(Off64_v(31 downto 0)), Rb_WrData,
                                                               r.Parity(ParOffLo_c), Rb_ByteEna, OffLoBits_c);
                        Word_v               := strobed(std_logic_vector(Off64_v(31 downto 0)), Rb_WrData,
                                                        Rb_ByteEna);
                        Off64_v(31 downto 0) := signed(Word_v);
                        -- The bits above the offset width are not stored
                        v.Offset := Off64_v(OW_c - 1 downto 0);
                    end if;

                when RegOffsetHi_c =>
                    if Runtime_g then
                        v.Parity(ParOffHi_c)  := ispWriteParity(std_logic_vector(Off64_v(63 downto 32)), Rb_WrData,
                                                                r.Parity(ParOffHi_c), Rb_ByteEna, OffHiBits_c);
                        Word_v                := strobed(std_logic_vector(Off64_v(63 downto 32)), Rb_WrData,
                                                         Rb_ByteEna);
                        Off64_v(63 downto 32) := signed(Word_v);
                        v.Offset              := Off64_v(OW_c - 1 downto 0);
                    end if;

                when RegGain_c =>
                    if Runtime_g then
                        Word_v              := strobed(std_logic_vector(resize(r.Gain, 32)), Rb_WrData, Rb_ByteEna);
                        v.Gain              := resize(unsigned(Word_v), GainBits_g);
                        v.Parity(ParGain_c) := ispWriteParity(std_logic_vector(resize(r.Gain, 32)), Rb_WrData,
                                                              r.Parity(ParGain_c), Rb_ByteEna, GainBits_g);
                    end if;

                when RegShift_c =>
                    if Runtime_g then
                        Word_v               := strobed(std_logic_vector(resize(r.Shift, 32)), Rb_WrData, Rb_ByteEna);
                        v.Shift              := unsigned(Word_v(6 downto 0));
                        v.Parity(ParShift_c) := ispWriteParity(std_logic_vector(resize(r.Shift, 32)), Rb_WrData,
                                                               r.Parity(ParShift_c), Rb_ByteEna, 7);
                    end if;

                when RegLow_c =>
                    if Runtime_g then
                        Word_v             := strobed(std_logic_vector(resize(r.Low, 32)), Rb_WrData, Rb_ByteEna);
                        v.Low              := resize(unsigned(Word_v), OutBits_g);
                        v.Parity(ParLow_c) := ispWriteParity(std_logic_vector(resize(r.Low, 32)), Rb_WrData,
                                                             r.Parity(ParLow_c), Rb_ByteEna, OutBits_g);
                    end if;

                when RegHigh_c =>
                    if Runtime_g then
                        Word_v              := strobed(std_logic_vector(resize(r.High, 32)), Rb_WrData, Rb_ByteEna);
                        v.High              := resize(unsigned(Word_v), OutBits_g);
                        v.Parity(ParHigh_c) := ispWriteParity(std_logic_vector(resize(r.High, 32)), Rb_WrData,
                                                              r.Parity(ParHigh_c), Rb_ByteEna, OutBits_g);
                    end if;

                when others =>
                    null;

            end case;

        end if;

        -- Sticky flags: the event wins over a clear in the same cycle (PNT-RG-02)
        if ClrFrm_v then
            v.FlagFraming := '0';
        end if;
        if FsErrFraming = '1' then
            v.FlagFraming := '1';
        end if;
        if ClrCfg_v then
            v.FlagConfig := '0';
        end if;
        if r.ErrConfig = '1' then
            v.FlagConfig := '1';
        end if;

        -- PT-4: register reads, answered in the next cycle
        v.RdValid := '0';
        if Rb_Rd = '1' then
            v.RdValid := '1';
            v.RdData  := (others => '0');
            Off64_v   := resize(r.Offset, 64);

            case to_integer(unsigned(Rb_Addr)) is

                when RegId_c =>
                    v.RdData := RegMapId_c;

                when RegImage_c =>
                    v.RdData := std_logic_vector(to_unsigned(ImageHeight_g - 1, 16)) &
                                std_logic_vector(to_unsigned(ImageWidth_g - 1, 16));

                when RegParam_c =>
                    v.RdData(ParamInBitsHi_c downto ParamInBitsLo_c)     := std_logic_vector(to_unsigned(InBits_g, 7));
                    v.RdData(ParamOutBitsHi_c downto ParamOutBitsLo_c)   := std_logic_vector(to_unsigned(OutBits_g, 6));
                    v.RdData(ParamGainBitsHi_c downto ParamGainBitsLo_c) := std_logic_vector(to_unsigned(GainBits_g, 5));
                    v.RdData(ParamMaxShiftHi_c downto ParamMaxShiftLo_c) := std_logic_vector(to_unsigned(MaxShift_g, 7));

                when RegCtrl_c =>
                    v.RdData(CtrlHold_c) := r.Hold;

                when RegStatus_c =>
                    v.RdData(StatusImageOpen_c)  := FsImageOpen;
                    v.RdData(StatusErrFraming_c) := r.FlagFraming;
                    v.RdData(StatusErrConfig_c)  := r.FlagConfig;

                when RegOffsetLo_c =>
                    v.RdData := std_logic_vector(Off64_v(31 downto 0));

                when RegOffsetHi_c =>
                    v.RdData := std_logic_vector(Off64_v(63 downto 32));

                when RegGain_c =>
                    v.RdData := std_logic_vector(resize(r.Gain, 32));

                when RegShift_c =>
                    v.RdData := std_logic_vector(resize(r.Shift, 32));

                when RegLow_c =>
                    v.RdData := std_logic_vector(resize(r.Low, 32));

                when RegHigh_c =>
                    v.RdData := std_logic_vector(resize(r.High, 32));

                when others =>
                    null;

            end case;

        end if;

        -- With Runtime_g false the parameter registers and the working set are the generics
        if not Runtime_g then
            v.Parity  := ParityRst_c;
            v.Offset  := GenOffset_c;
            v.Gain    := GenGain_c;
            v.Shift   := GenShift_c;
            v.Low     := GenLow_c;
            v.High    := GenHigh_c;
            v.WOffset := GenOffset_c;
            v.WGain   := GenGain_c;
            v.WShift  := GenShift_c;
            v.WLow    := GenLow_c;
            v.WHigh   := GenHigh_c;
        end if;

        r_next <= v;
    end process;

    Out_Valid      <= r.PFlags(Stages_c)(0);
    Out_Data       <= r.OutData;
    Out_Last       <= r.PFlags(Stages_c)(1);
    Out_User       <= r.PFlags(Stages_c)(3 downto 2);
    Err_Framing    <= FsErrFraming;
    Err_Config     <= r.ErrConfig;
    Stat_ImageOpen <= FsImageOpen;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Offset      <= GenOffset_c;
                r.Gain        <= GenGain_c;
                r.Shift       <= GenShift_c;
                r.Low         <= GenLow_c;
                r.High        <= GenHigh_c;
                r.Parity      <= ParityRst_c;
                r.Hold        <= '0';
                r.FlagFraming <= '0';
                r.FlagConfig  <= '0';
                r.RdValid     <= '0';
                r.WOffset     <= GenOffset_c;
                r.WGain       <= GenGain_c;
                r.WShift      <= GenShift_c;
                r.WLow        <= GenLow_c;
                r.WHigh       <= GenHigh_c;
                r.ErrConfig   <= '0';
                r.PFlags      <= (others => (others => '0'));
            end if;
        end if;
    end process;

end architecture;
