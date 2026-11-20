---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Window generator of OpenISP: delivers for every reference pixel of an image the window of
-- WinX_g x WinY_g pixels around it as one beat. The anchor, the stride and the border mode (valid,
-- zero, replicate, mirror) are generics. The lines above are kept in WinY_g - 1 ECC-protected line
-- buffers (olo_ft_delay); the windows at the right and the lower border are completed by virtual
-- columns and lines that the module generates without input.
--
-- Documentation: hdl/isp_window/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_base_pkg_string.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_window is
    generic (
        -- Dimensions of the input image (W, H) and bits per pixel
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        PixelBits_g   : positive;
        -- Window, anchor (reference pixel in the window), stride and border mode
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        AnchorX_g     : natural  := (WinX_g - 1) / 2;
        AnchorY_g     : natural  := (WinY_g - 1) / 2;
        StrideX_g     : positive := 1;
        StrideY_g     : positive := 1;
        BorderMode_g  : string   := "replicate";
        -- Line buffers (Open Logic olo_ft_delay)
        EccPipeline_g : natural  := 1;
        Resource_g    : string   := "AUTO";
        RamStyle_g    : string   := "auto"
    );
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Input pixel stream
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        In_Data        : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last        : in    std_logic;
        In_User        : in    std_logic_vector(1 downto 0);
        -- Window stream: element k = j x WinX_g + i in bits (k + 1) x PixelBits_g - 1 downto k x PixelBits_g
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic;
        Out_Data       : out   std_logic_vector(WinX_g * WinY_g * PixelBits_g - 1 downto 0);
        Out_Last       : out   std_logic;
        Out_User       : out   std_logic_vector(1 downto 0);
        -- Status
        Err_Framing    : out   std_logic;
        Stat_ImageOpen : out   std_logic;
        Stat_EccSec    : out   std_logic;
        Stat_EccDed    : out   std_logic;
        -- Error injection into the line buffers: codeword of line buffer t in bits t x C - 1 downto (t - 1) x C
        ErrInj_BitFlip : in    std_logic_vector(maximum(WinY_g - 1, 1) * eccCodewordWidth(PixelBits_g) - 1 downto 0)
                                         := (others => '0');
        ErrInj_Valid   : in    std_logic := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_window is

    constant W_c  : positive := ImageWidth_g;
    constant H_c  : positive := ImageHeight_g;
    constant PB_c : positive := PixelBits_g;
    constant CW_c : positive := eccCodewordWidth(PixelBits_g);
    -- Columns right of the reference pixel and lines below it
    -- (limited to 0, so that an anchor out of range reaches the check of WIN-CF-01 with its message)
    constant Rr_c : natural := maximum(WinX_g - 1 - AnchorX_g, 0);
    constant Rb_c : natural := maximum(WinY_g - 1 - AnchorY_g, 0);

    -- Border modes
    constant Valid_c     : boolean := BorderMode_g = "valid";
    constant Zero_c      : boolean := BorderMode_g = "zero";
    constant Replicate_c : boolean := BorderMode_g = "replicate";
    constant Mirror_c    : boolean := BorderMode_g = "mirror";

    -- Virtual columns and lines (none in the mode valid)
    function virtual (n : natural) return natural is
    begin
        if Valid_c then
            return 0;
        end if;
        return n;
    end function;

    constant VCols_c  : natural := virtual(Rr_c);
    constant VLines_c : natural := virtual(Rb_c);

    -- Reference pixels: first X0, Y0 and last XL, YL (specification, section 1.1)
    function firstRef (anchor : natural) return natural is
    begin
        if Valid_c then
            return anchor;
        end if;
        return 0;
    end function;

    constant X0_c : natural := firstRef(AnchorX_g);
    constant Y0_c : natural := firstRef(AnchorY_g);
    -- Output dimensions (isp_pkg, PKG-06); at least 1, so that an image smaller than the window in the border mode
    -- valid reaches the configuration check, which names the generic
    constant Wo_c : positive := maximum(ispWinOut(W_c, WinX_g, StrideX_g, BorderMode_g), 1);
    constant Ho_c : positive := maximum(ispWinOut(H_c, WinY_g, StrideY_g, BorderMode_g), 1);
    constant XL_c : natural  := X0_c + (Wo_c - 1) * StrideX_g;
    constant YL_c : natural  := Y0_c + (Ho_c - 1) * StrideY_g;

    -- EccPipeline_g limited to the range of the Open Logic delay and an unknown Resource_g replaced by AUTO, so that a
    -- value out of range elaborates the delays and stops at the configuration check, which names the generic.
    -- Open Logic takes Resource_g without regard to case
    constant EccPipe_c    : natural := minimum(EccPipeline_g, 1);
    constant Bram_c       : boolean := compareNoCase(Resource_g, "BRAM");
    constant ResourceOk_c : boolean := compareNoCase(Resource_g, "AUTO") or compareNoCase(Resource_g, "SRL") or Bram_c;
    constant Resource_c   : string  := choose(ResourceOk_c, Resource_g, "AUTO");

    -- Event positions: columns up to W + Rr - 1, lines up to H + Rb - 1; one value more, so that the column W and
    -- the line H have a value also where no virtual column or line exists
    constant XW_c : positive := ispPosWidth(W_c + VCols_c + 1);
    constant YW_c : positive := ispPosWidth(H_c + VLines_c + 1);

    -- Row selection: row j of a column takes delay output d (0: the pixel of the event) or 0 (index WinY_g)
    subtype Sel_t is natural range 0 to WinY_g;
    type RowSel_t is array (0 to WinY_g - 1) of Sel_t;

    -- Selection of the rows for the event line ye (specification, section 6)
    function rowSelect (ye : natural) return RowSel_t is
        variable Sel_v  : RowSel_t;
        variable Line_v : integer;
        variable Map_v  : integer;
    begin

        for j in 0 to WinY_g - 1 loop
            Line_v := ye - (WinY_g - 1) + j;
            if Line_v >= 0 and Line_v <= H_c - 1 then
                Map_v := Line_v;
            elsif Zero_c or Valid_c then
                Map_v := -1;
            elsif Replicate_c then
                Map_v := 0 when Line_v < 0 else H_c - 1;
            else
                Map_v := -Line_v when Line_v < 0 else 2 * (H_c - 1) - Line_v;
            end if;
            -- A line that has not arrived (only in lines without a window) reads as 0
            if Map_v < 0 or ye - Map_v < 0 or ye - Map_v > WinY_g - 1 then
                Sel_v(j) := WinY_g;
            else
                Sel_v(j) := ye - Map_v;
            end if;
        end loop;

        return Sel_v;
    end function;

    -- Event states (architecture, section 5)
    type State_t is (Pix_s, HCol_s, VPix_s);

    type Column_t is array (0 to WinY_g - 1) of std_logic_vector(PB_c - 1 downto 0);
    type Window_t is array (0 to WinX_g - 1) of Column_t;

    type TwoProcess_r is record
        State    : State_t;
        -- Virtual column (HCOL) or column of the virtual line (VPIX), line of the virtual line
        VCol     : unsigned(XW_c - 1 downto 0);
        VLine    : unsigned(YW_c - 1 downto 0);
        -- Line of the next event and its row selection
        NextLine : unsigned(YW_c - 1 downto 0);
        RowSel   : RowSel_t;
        -- Stride counters
        XStr     : natural range 0 to StrideX_g - 1;
        YStr     : natural range 0 to StrideY_g - 1;
        -- Window register and output
        Win      : Window_t;
        OutValid : std_logic;
        OutLast  : std_logic;
        OutUser  : std_logic_vector(1 downto 0);
        EccSec   : std_logic;
        EccDed   : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    -- WN-1 Frame sync
    signal FsValid : std_logic;
    signal FsReady : std_logic;
    signal FsData  : std_logic_vector(PB_c - 1 downto 0);
    signal FsPosX  : std_logic_vector(ispPosWidth(W_c) - 1 downto 0);
    signal FsPosY  : std_logic_vector(ispPosWidth(H_c) - 1 downto 0);

    -- WN-3 Line buffers: input of delay 1, outputs of all delays (index 0 is the pixel of the event)
    signal Shift   : std_logic;
    signal EvPixel : std_logic_vector(PB_c - 1 downto 0);
    signal DlyOut  : Column_t;
    signal DlySec  : std_logic_vector(WinY_g - 1 downto 0);
    signal DlyDed  : std_logic_vector(WinY_g - 1 downto 0);

begin

    -- WIN-CF-01, WIN-CF-02, WIN-CF-05: the generics outside their range stop the elaboration
    assert ImageWidth_g >= WinX_g and ImageWidth_g <= 65536
        report "isp_window: ImageWidth_g must be WinX_g to 65536"
        severity failure;
    assert ImageHeight_g >= WinY_g and ImageHeight_g <= 65536
        report "isp_window: ImageHeight_g must be WinY_g to 65536"
        severity failure;
    assert PixelBits_g <= 32
        report "isp_window: PixelBits_g must be 1 to 32"
        severity failure;
    assert WinX_g <= 16
        report "isp_window: WinX_g must be 1 to 16"
        severity failure;
    assert WinY_g <= 16
        report "isp_window: WinY_g must be 1 to 16"
        severity failure;
    assert AnchorX_g <= WinX_g - 1
        report "isp_window: AnchorX_g must be 0 to WinX_g - 1"
        severity failure;
    assert AnchorY_g <= WinY_g - 1
        report "isp_window: AnchorY_g must be 0 to WinY_g - 1"
        severity failure;
    assert StrideX_g <= 16
        report "isp_window: StrideX_g must be 1 to 16"
        severity failure;
    assert StrideY_g <= 16
        report "isp_window: StrideY_g must be 1 to 16"
        severity failure;
    assert Valid_c or Zero_c or Replicate_c or Mirror_c
        report "isp_window: BorderMode_g must be valid, zero, replicate or mirror"
        severity failure;
    assert not Mirror_c or WinX_g = 1 or (WinX_g mod 2 = 1 and AnchorX_g = (WinX_g - 1) / 2)
        report "isp_window: BorderMode_g mirror needs an odd WinX_g with AnchorX_g in the middle"
        severity failure;
    assert not Mirror_c or WinY_g = 1 or (WinY_g mod 2 = 1 and AnchorY_g = (WinY_g - 1) / 2)
        report "isp_window: BorderMode_g mirror needs an odd WinY_g with AnchorY_g in the middle"
        severity failure;
    assert EccPipeline_g <= 1
        report "isp_window: EccPipeline_g must be 0 or 1"
        severity failure;
    assert ResourceOk_c
        report "isp_window: Resource_g must be AUTO, SRL or BRAM"
        severity failure;
    assert not Bram_c or WinY_g = 1 or ImageWidth_g >= 3 + EccPipeline_g
        report "isp_window: ImageWidth_g must be at least 3 + EccPipeline_g for Resource_g BRAM"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- WN-1 Frame sync
    -----------------------------------------------------------------------------------------------
    i_frame_sync : entity work.isp_frame_sync
        generic map (
            ImageWidth_g  => W_c,
            ImageHeight_g => H_c,
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
            Out_Valid      => FsValid,
            Out_Ready      => FsReady,
            Out_Data       => FsData,
            Out_Last       => open,
            Out_User       => open,
            Out_PosX       => FsPosX,
            Out_PosY       => FsPosY,
            Err_Framing    => Err_Framing,
            Stat_ImageOpen => Stat_ImageOpen
        );

    -----------------------------------------------------------------------------------------------
    -- WN-3 Line buffers
    -----------------------------------------------------------------------------------------------
    DlyOut(0) <= EvPixel;
    DlySec(0) <= '0';
    DlyDed(0) <= '0';

    g_delays : for t in 1 to WinY_g - 1 generate

        i_delay : entity olo.olo_ft_delay
            generic map (
                Width_g       => PB_c,
                Delay_g       => W_c,
                Resource_g    => Resource_c,
                RstState_g    => true,
                RamStyle_g    => RamStyle_g,
                EccPipeline_g => EccPipe_c
            )
            port map (
                Clk               => Clk,
                Rst               => Rst,
                In_Data           => DlyOut(t - 1),
                In_Valid          => Shift,
                Out_Data          => DlyOut(t),
                Out_EccSec        => DlySec(t),
                Out_EccDed        => DlyDed(t),
                In_ErrInj_BitFlip => ErrInj_BitFlip(t * CW_c - 1 downto (t - 1) * CW_c),
                In_ErrInj_Valid   => ErrInj_Valid
            );

    end generate;

    -----------------------------------------------------------------------------------------------
    -- WN-2 Event control, WN-4 Window register, WN-5 Output
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Event_v : boolean;
        variable Shift_v : boolean;
        variable Xe_v    : unsigned(XW_c - 1 downto 0);
        variable Ye_v    : unsigned(YW_c - 1 downto 0);
        variable Pixel_v : std_logic_vector(PB_c - 1 downto 0);
        variable Col_v   : Column_t;
        variable Old_v   : Window_t;
        variable EndLn_v : boolean;
        variable RefX_v  : boolean;
        variable RefY_v  : boolean;
        variable Next_v  : natural;
        variable Sel_v   : RowSel_t;
        variable Used_v  : boolean;
        variable XStr_v  : natural range 0 to StrideX_g - 1;
        variable YStr_v  : natural range 0 to StrideY_g - 1;
    begin
        v        := r;
        v.EccSec := '0';
        v.EccDed := '0';

        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;

        -- WN-2: an event waits while the window register holds a window that the consumer has not taken
        Event_v := false;
        Shift_v := false;
        EndLn_v := false;
        FsReady <= '0';
        Xe_v    := (others => '0');
        Ye_v    := r.NextLine;
        Pixel_v := (others => '0');
        if r.OutValid = '0' or Out_Ready = '1' then

            case r.State is

                when Pix_s =>
                    if FsValid = '1' then
                        -- PIX: the position from the frame sync; pixel (0, 0) restarts the counters (WIN-FT-03)
                        FsReady <= '1';
                        Event_v := true;
                        Shift_v := true;
                        Xe_v    := resize(unsigned(FsPosX), XW_c);
                        Ye_v    := resize(unsigned(FsPosY), YW_c);
                        Pixel_v := FsData;
                        if unsigned(FsPosX) = W_c - 1 then
                            EndLn_v := VCols_c = 0;
                            if VCols_c > 0 then
                                v.State := HCol_s;
                                v.VCol  := (others => '0');
                            elsif unsigned(FsPosY) = H_c - 1 and VLines_c > 0 then
                                v.State := VPix_s;
                                v.VCol  := (others => '0');
                                v.VLine := to_unsigned(H_c, YW_c);
                            end if;
                        end if;
                    end if;

                when HCol_s =>
                    -- HCOL: virtual column W + m, no shift of the line buffers
                    Event_v := true;
                    Xe_v    := to_unsigned(W_c, XW_c) + r.VCol;
                    if to_integer(r.VCol) = VCols_c - 1 then
                        EndLn_v := true;
                        if r.NextLine = H_c - 1 + VLines_c then
                            v.State := Pix_s;
                        elsif r.NextLine >= H_c - 1 then
                            v.State := VPix_s;
                            v.VCol  := (others => '0');
                            v.VLine := r.NextLine + 1;
                        else
                            v.State := Pix_s;
                        end if;
                    else
                        v.VCol := r.VCol + 1;
                    end if;

                when VPix_s =>
                    -- VPIX: a pixel of value 0 of a virtual line; the line buffers shift
                    Event_v := true;
                    Shift_v := true;
                    Xe_v    := r.VCol;
                    Ye_v    := r.VLine;
                    if r.VCol = W_c - 1 then
                        if VCols_c > 0 then
                            v.State := HCol_s;
                            v.VCol  := (others => '0');
                        else
                            EndLn_v := true;
                            if r.VLine = H_c - 1 + VLines_c then
                                v.State := Pix_s;
                            else
                                v.VCol  := (others => '0');
                                v.VLine := r.VLine + 1;
                            end if;
                        end if;
                    else
                        v.VCol := r.VCol + 1;
                    end if;

                when others =>
                    v.State := Pix_s;

            end case;

        end if;

        Shift   <= '1' when Shift_v else '0';
        EvPixel <= Pixel_v;

        if Event_v then
            -- Pixel (0, 0) restarts the row selection and the stride counters (WIN-FT-03)
            Sel_v  := r.RowSel;
            XStr_v := r.XStr;
            YStr_v := r.YStr;
            if Xe_v = 0 then
                XStr_v := 0;
            end if;
            if r.State = Pix_s and Xe_v = 0 and Ye_v = 0 then
                Sel_v  := rowSelect(0);
                YStr_v := 0;
            end if;

            -- WN-4: the column of the event with the rows of the line (upper and lower border)
            for j in 0 to WinY_g - 1 loop
                if Sel_v(j) = WinY_g then
                    Col_v(j) := (others => '0');
                else
                    Col_v(j) := DlyOut(Sel_v(j));
                end if;
            end loop;

            -- ECC status of the line buffers, sampled in the pixel events (WIN-FT-02)
            -- Only the line buffers that the row selection of the event uses count: the lines above the image hold the
            -- image before (or after power-up any content), which never reaches a window (WIN-FT-02)
            if Shift_v then

                for d in 1 to WinY_g - 1 loop
                    Used_v := false;

                    for j in 0 to WinY_g - 1 loop
                        if Sel_v(j) = d then
                            Used_v := true;
                        end if;
                    end loop;

                    if Used_v and DlySec(d) = '1' then
                        v.EccSec := '1';
                    end if;
                    if Used_v and DlyDed(d) = '1' then
                        v.EccDed := '1';
                    end if;
                end loop;

            end if;

            -- WN-4: left and right border
            Old_v := r.Win;
            if Xe_v >= W_c then
                -- HCOL m = Xe_v - W + 1
                if Zero_c then
                    Col_v := (others => (others => '0'));
                elsif Replicate_c then
                    Col_v := Old_v(WinX_g - 1);
                elsif Mirror_c then
                    Col_v := Old_v(WinX_g - 1 - (2 * (to_integer(Xe_v) - W_c + 1) - 1));
                end if;
            end if;

            -- Shift by one column, the new column last
            for i in 0 to WinX_g - 2 loop
                v.Win(i) := Old_v(i + 1);
            end loop;

            v.Win(WinX_g - 1) := Col_v;

            if Xe_v = 0 then
                if Zero_c then
                    v.Win             := (others => (others => (others => '0')));
                    v.Win(WinX_g - 1) := Col_v;
                elsif Replicate_c then
                    v.Win := (others => Col_v);
                end if;
            end if;
            if Mirror_c and Xe_v >= 1 and Xe_v <= AnchorX_g and Xe_v < W_c then
                v.Win(WinX_g - 1 - 2 * to_integer(Xe_v)) := Col_v;
            end if;

            -- WN-5: a window of a reference pixel (x, y) = (xe - Rr, ye - Rb)
            RefX_v := Xe_v >= X0_c + Rr_c and Xe_v <= XL_c + Rr_c and XStr_v = 0;
            RefY_v := Ye_v >= Y0_c + Rb_c and Ye_v <= YL_c + Rb_c and YStr_v = 0;
            v.XStr := XStr_v;
            v.YStr := YStr_v;
            if Xe_v >= X0_c + Rr_c then
                v.XStr := (XStr_v + 1) mod StrideX_g;
            end if;
            if RefX_v and RefY_v then
                v.OutValid := '1';
                v.OutLast  := '1' when Xe_v = XL_c + Rr_c else '0';
                if Ye_v = Y0_c + Rb_c and Y0_c = YL_c then
                    v.OutUser := SeqOnly_c;
                elsif Ye_v = Y0_c + Rb_c then
                    v.OutUser := SeqFirst_c;
                elsif Ye_v = YL_c + Rb_c then
                    v.OutUser := SeqLast_c;
                else
                    v.OutUser := SeqCont_c;
                end if;
            end if;

            -- End of a line: the stride counters, the line of the next event and its row selection
            if EndLn_v then
                v.XStr := 0;
                if Ye_v >= Y0_c + Rb_c then
                    v.YStr := (YStr_v + 1) mod StrideY_g;
                end if;
                if Ye_v >= H_c - 1 + VLines_c then
                    Next_v := 0;
                    v.YStr := 0;
                else
                    Next_v := to_integer(Ye_v) + 1;
                end if;
                v.NextLine := to_unsigned(Next_v, YW_c);
                v.RowSel   := rowSelect(Next_v);
            end if;
        end if;

        r_next <= v;
    end process;

    -- WN-5: the window register is the output
    g_out : for i in 0 to WinX_g - 1 generate

        g_rows : for j in 0 to WinY_g - 1 generate
            Out_Data(((j * WinX_g + i) + 1) * PB_c - 1 downto (j * WinX_g + i) * PB_c) <= r.Win(i)(j);
        end generate;

    end generate;

    Out_Valid   <= r.OutValid;
    Out_Last    <= r.OutLast;
    Out_User    <= r.OutUser;
    Stat_EccSec <= r.EccSec;
    Stat_EccDed <= r.EccDed;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Pix_s;
                r.VCol     <= (others => '0');
                r.VLine    <= (others => '0');
                r.NextLine <= (others => '0');
                r.RowSel   <= rowSelect(0);
                r.XStr     <= 0;
                r.YStr     <= 0;
                r.OutValid <= '0';
                r.EccSec   <= '0';
                r.EccDed   <= '0';
            end if;
        end if;
    end process;

end architecture;
