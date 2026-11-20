---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Selects a region of interest of RoiWidth_g x RoiHeight_g pixels from every image of
-- ImageWidth_g x ImageHeight_g pixels and outputs it as an image of its own, one stream packet
-- per line. The position of the region comes from the generics or, with RuntimeRoi_g, from the
-- register ROI_POS, which is read with every image start, checked against the image and its parity
-- bit, and replaced by the generics when it is rejected (Err_Config).
--
-- Documentation: hdl/isp_crop/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.isp_pkg.all;
    use work.isp_crop_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_crop is
    generic (
        -- Dimensions of the input image (W, H) and bits per pixel
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        PixelBits_g   : positive;
        -- Size of the region of interest, which is the output image
        RoiWidth_g    : positive;
        RoiHeight_g   : positive;
        -- Position of the region; with RuntimeRoi_g the reset value of ROI_POS
        RoiX_g        : natural := 0;
        RoiY_g        : natural := 0;
        RuntimeRoi_g  : boolean := false
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
        -- Output pixel stream: the region, one packet per line
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(PixelBits_g - 1 downto 0);
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
architecture rtl of isp_crop is

    constant XW_c : positive := ispPosWidth(ImageWidth_g);
    constant YW_c : positive := ispPosWidth(ImageHeight_g);

    -- Reset value of ROI_POS: Y in 31:16, X in 15:0
    constant RoiPosRst_c : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(RoiY_g mod 65536, 16)) & std_logic_vector(to_unsigned(RoiX_g mod 65536, 16));

    -- Largest valid position of the region (CRP-ER-03)
    constant MaxX_c : unsigned(15 downto 0) := to_unsigned((ImageWidth_g - RoiWidth_g) mod 65536, 16);
    constant MaxY_c : unsigned(15 downto 0) := to_unsigned((ImageHeight_g - RoiHeight_g) mod 65536, 16);

    -- Limits of the region from the generics
    constant GenX0_c : unsigned(XW_c - 1 downto 0) := to_unsigned(RoiX_g mod 2 ** XW_c, XW_c);
    constant GenY0_c : unsigned(YW_c - 1 downto 0) := to_unsigned(RoiY_g mod 2 ** YW_c, YW_c);
    constant GenX1_c : unsigned(XW_c - 1 downto 0) := to_unsigned((RoiX_g + RoiWidth_g - 1) mod 2 ** XW_c, XW_c);
    constant GenY1_c : unsigned(YW_c - 1 downto 0) := to_unsigned((RoiY_g + RoiHeight_g - 1) mod 2 ** YW_c, YW_c);

    type TwoProcess_r is record
        -- CR-2 Position stage and the limits of the region in use
        PosValid    : std_logic;
        PosData     : std_logic_vector(PixelBits_g - 1 downto 0);
        PosX        : unsigned(XW_c - 1 downto 0);
        PosY        : unsigned(YW_c - 1 downto 0);
        X0          : unsigned(XW_c - 1 downto 0);
        X1          : unsigned(XW_c - 1 downto 0);
        Y0          : unsigned(YW_c - 1 downto 0);
        Y1          : unsigned(YW_c - 1 downto 0);
        ErrConfig   : std_logic;
        -- CR-3 Output register
        OutValid    : std_logic;
        OutData     : std_logic_vector(PixelBits_g - 1 downto 0);
        OutLast     : std_logic;
        OutUser     : std_logic_vector(1 downto 0);
        -- CR-4 Registers
        RoiPos      : std_logic_vector(31 downto 0);
        RoiPar      : std_logic;
        FlagFraming : std_logic;
        FlagConfig  : std_logic;
        RdValid     : std_logic;
        RdData      : std_logic_vector(31 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- CR-1 Frame sync
    signal FsValid      : std_logic;
    signal FsReady      : std_logic;
    signal FsData       : std_logic_vector(PixelBits_g - 1 downto 0);
    signal FsPosX       : std_logic_vector(XW_c - 1 downto 0);
    signal FsPosY       : std_logic_vector(YW_c - 1 downto 0);
    signal FsErrFraming : std_logic;
    signal FsImageOpen  : std_logic;

    -- Register bus of the AXI4-Lite slave
    signal Rb_Addr    : std_logic_vector(7 downto 0);
    signal Rb_Wr      : std_logic;
    signal Rb_ByteEna : std_logic_vector(3 downto 0);
    signal Rb_WrData  : std_logic_vector(31 downto 0);
    signal Rb_Rd      : std_logic;

begin

    -- CRP-CF-01: the generics outside their range stop the elaboration
    assert ImageWidth_g <= 65536
        report "isp_crop: ImageWidth_g must be 1 to 65536"
        severity failure;
    assert ImageHeight_g <= 65536
        report "isp_crop: ImageHeight_g must be 1 to 65536"
        severity failure;
    assert PixelBits_g <= 64
        report "isp_crop: PixelBits_g must be 1 to 64"
        severity failure;
    assert RoiX_g <= ImageWidth_g - 1
        report "isp_crop: RoiX_g must be 0 to ImageWidth_g - 1"
        severity failure;
    assert RoiY_g <= ImageHeight_g - 1
        report "isp_crop: RoiY_g must be 0 to ImageHeight_g - 1"
        severity failure;
    assert RoiWidth_g <= ImageWidth_g - RoiX_g
        report "isp_crop: RoiWidth_g must be 1 to ImageWidth_g - RoiX_g"
        severity failure;
    assert RoiHeight_g <= ImageHeight_g - RoiY_g
        report "isp_crop: RoiHeight_g must be 1 to ImageHeight_g - RoiY_g"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- CR-1 Frame sync
    -----------------------------------------------------------------------------------------------
    i_frame_sync : entity work.isp_frame_sync
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
            Out_Valid      => FsValid,
            Out_Ready      => FsReady,
            Out_Data       => FsData,
            Out_Last       => open,
            Out_User       => open,
            Out_PosX       => FsPosX,
            Out_PosY       => FsPosY,
            Err_Framing    => FsErrFraming,
            Stat_ImageOpen => FsImageOpen
        );

    -----------------------------------------------------------------------------------------------
    -- CR-4 AXI4-Lite slave
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
    -- CR-2 Position stage, CR-3 Selection and output register, CR-4 Registers
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v           : TwoProcess_r;
        variable OutFree_v   : boolean;
        variable Inside_v    : boolean;
        variable StageFree_v : boolean;
        variable RegX_v      : unsigned(15 downto 0);
        variable RegY_v      : unsigned(15 downto 0);
        variable Accept_v    : boolean;
        variable ClrFrm_v    : boolean;
        variable ClrCfg_v    : boolean;
    begin
        v           := r;
        v.ErrConfig := '0';

        -- CR-3: the output register is free when it is empty or read in this cycle
        OutFree_v := r.OutValid = '0' or Out_Ready = '1';
        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;

        -- CR-3: a pixel in the position stage, inside the region (the comparisons only with a pixel)
        Inside_v := r.PosValid = '1' and r.PosX >= r.X0 and r.PosX <= r.X1 and r.PosY >= r.Y0 and r.PosY <= r.Y1;

        -- CR-2: a pixel leaves the stage when it is outside the region (dropped) or the output takes it
        StageFree_v := r.PosValid = '0' or not Inside_v or OutFree_v;

        if Inside_v and OutFree_v then
            v.OutValid := '1';
            v.OutData  := r.PosData;
            v.OutLast  := '1' when r.PosX = r.X1 else '0';
            if RoiHeight_g = 1 then
                v.OutUser := SeqOnly_c;
            elsif r.PosY = r.Y0 then
                v.OutUser := SeqFirst_c;
            elsif r.PosY = r.Y1 then
                v.OutUser := SeqLast_c;
            else
                v.OutUser := SeqCont_c;
            end if;
        end if;

        if StageFree_v then
            v.PosValid := '0';
        end if;

        -- CR-2: the stage takes the next pixel of the frame sync when it is free
        if StageFree_v then
            FsReady <= '1';
        else
            FsReady <= '0';
        end if;

        if FsValid = '1' and StageFree_v then
            v.PosValid := '1';
            v.PosData  := FsData;
            v.PosX     := unsigned(FsPosX);
            v.PosY     := unsigned(FsPosY);

            -- Pixel (0, 0): the limits of the region of this image (CRP-FN-06, CRP-ER-03, CRP-ER-04)
            if RuntimeRoi_g and unsigned(FsPosX) = 0 and unsigned(FsPosY) = 0 then
                RegX_v   := unsigned(r.RoiPos(15 downto 0));
                RegY_v   := unsigned(r.RoiPos(31 downto 16));
                Accept_v := RegX_v <= MaxX_c and RegY_v <= MaxY_c and (xor r.RoiPos) = r.RoiPar;
                if Accept_v then
                    v.X0 := resize(RegX_v, XW_c);
                    v.Y0 := resize(RegY_v, YW_c);
                    v.X1 := resize(RegX_v + (RoiWidth_g - 1), XW_c);
                    v.Y1 := resize(RegY_v + (RoiHeight_g - 1), YW_c);
                else
                    v.X0        := GenX0_c;
                    v.Y0        := GenY0_c;
                    v.X1        := GenX1_c;
                    v.Y1        := GenY1_c;
                    v.ErrConfig := '1';
                end if;
            end if;
        end if;

        -- With constant limits the comparisons are comparisons with constants
        if not RuntimeRoi_g then
            v.X0 := GenX0_c;
            v.Y0 := GenY0_c;
            v.X1 := GenX1_c;
            v.Y1 := GenY1_c;
        end if;

        -- CR-4: register writes
        ClrFrm_v := false;
        ClrCfg_v := false;
        if Rb_Wr = '1' then

            case to_integer(unsigned(Rb_Addr)) is

                when RegRoiPos_c =>
                    if RuntimeRoi_g then

                        for b in 0 to 3 loop
                            if Rb_ByteEna(b) = '1' then
                                v.RoiPos(8 * b + 7 downto 8 * b) := Rb_WrData(8 * b + 7 downto 8 * b);
                            end if;
                        end loop;

                        -- A write of every byte sets the parity bit for the written value, a write that keeps a
                        -- byte keeps a mismatch (CRP-RG-03, PKG-08)
                        v.RoiPar := ispWriteParity(r.RoiPos, Rb_WrData, r.RoiPar, Rb_ByteEna, 32);
                    end if;

                when RegStatus_c =>
                    if Rb_ByteEna(1) = '1' then
                        ClrFrm_v := Rb_WrData(StatusErrFraming_c) = '1';
                        ClrCfg_v := Rb_WrData(StatusErrConfig_c) = '1';
                    end if;

                when RegInject_c =>
                    if RuntimeRoi_g and Rb_ByteEna(0) = '1' and Rb_WrData(InjectRoiPosParity_c) = '1' then
                        v.RoiPar := not r.RoiPar;
                    end if;

                when others =>
                    null;

            end case;

        end if;

        -- Sticky flags: the event wins over a clear in the same cycle (CRP-RG-02)
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

        -- CR-4: register reads, answered in the next cycle
        v.RdValid := '0';
        if Rb_Rd = '1' then
            v.RdValid := '1';
            v.RdData  := (others => '0');

            case to_integer(unsigned(Rb_Addr)) is

                when RegId_c =>
                    v.RdData := RegMapId_c;

                when RegImage_c =>
                    v.RdData := std_logic_vector(to_unsigned(ImageHeight_g - 1, 16)) &
                                std_logic_vector(to_unsigned(ImageWidth_g - 1, 16));

                when RegRoiSize_c =>
                    v.RdData := std_logic_vector(to_unsigned(RoiHeight_g - 1, 16)) &
                                std_logic_vector(to_unsigned(RoiWidth_g - 1, 16));

                when RegRoiPos_c =>
                    v.RdData := r.RoiPos;

                when RegStatus_c =>
                    v.RdData(StatusImageOpen_c)  := FsImageOpen;
                    v.RdData(StatusErrFraming_c) := r.FlagFraming;
                    v.RdData(StatusErrConfig_c)  := r.FlagConfig;

                when others =>
                    null;

            end case;

        end if;

        -- With RuntimeRoi_g false ROI_POS shows the generics
        if not RuntimeRoi_g then
            v.RoiPos := RoiPosRst_c;
            v.RoiPar := xor RoiPosRst_c;
        end if;

        r_next <= v;
    end process;

    Out_Valid      <= r.OutValid;
    Out_Data       <= r.OutData;
    Out_Last       <= r.OutLast;
    Out_User       <= r.OutUser;
    Err_Framing    <= FsErrFraming;
    Err_Config     <= r.ErrConfig;
    Stat_ImageOpen <= FsImageOpen;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.PosValid    <= '0';
                r.X0          <= GenX0_c;
                r.X1          <= GenX1_c;
                r.Y0          <= GenY0_c;
                r.Y1          <= GenY1_c;
                r.ErrConfig   <= '0';
                r.OutValid    <= '0';
                r.RoiPos      <= RoiPosRst_c;
                r.RoiPar      <= xor RoiPosRst_c;
                r.FlagFraming <= '0';
                r.FlagConfig  <= '0';
                r.RdValid     <= '0';
            end if;
        end if;
    end process;

end architecture;
