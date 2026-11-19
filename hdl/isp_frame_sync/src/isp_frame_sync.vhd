---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Input side of every OpenISP module: takes an image in any division into stream packets and
-- delivers complete images of ImageWidth_g x ImageHeight_g pixels, one stream packet per line, with
-- the position of every pixel. An image that is too short is completed with zeros at the next image
-- start, pixels that belong to no image are discarded, and every deviation pulses Err_Framing.
--
-- Documentation: hdl/isp_frame_sync/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.isp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_frame_sync is
    generic (
        -- Dimensions of the image (W, H) and bits per pixel
        ImageWidth_g  : positive;
        ImageHeight_g : positive;
        PixelBits_g   : positive
    );
    port (
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Input pixel stream: Last on the last beat of a stream packet, User the sequence flags
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        In_Data        : in    std_logic_vector(PixelBits_g - 1 downto 0);
        In_Last        : in    std_logic;
        In_User        : in    std_logic_vector(1 downto 0);
        -- Output pixel stream: one packet per line, with the position of every pixel
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic;
        Out_Data       : out   std_logic_vector(PixelBits_g - 1 downto 0);
        Out_Last       : out   std_logic;
        Out_User       : out   std_logic_vector(1 downto 0);
        Out_PosX       : out   std_logic_vector(ispPosWidth(ImageWidth_g) - 1 downto 0);
        Out_PosY       : out   std_logic_vector(ispPosWidth(ImageHeight_g) - 1 downto 0);
        -- Status
        Err_Framing    : out   std_logic;
        Stat_ImageOpen : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_frame_sync is

    constant XW_c : positive := ispPosWidth(ImageWidth_g);
    constant YW_c : positive := ispPosWidth(ImageHeight_g);

    -- Image limits: the only place where the image size enters the logic
    constant LastX_c : unsigned(XW_c - 1 downto 0) := to_unsigned(ImageWidth_g - 1, XW_c);
    constant LastY_c : unsigned(YW_c - 1 downto 0) := to_unsigned(ImageHeight_g - 1, YW_c);

    -- An image of one pixel ends with its image start
    constant OnePixel_c : boolean := ImageWidth_g = 1 and ImageHeight_g = 1;

    -- Input stage word: pixel, Last, sequence flags, first beat of a packet
    constant StgWidth_c : positive := PixelBits_g + 4;

    -- Idle_s: no image open; Image_s: pixels of the open image; Pad_s: missing pixels of a short image
    type State_t is (Idle_s, Image_s, Pad_s);

    type TwoProcess_r is record
        State      : State_t;
        PosX       : unsigned(XW_c - 1 downto 0);
        PosY       : unsigned(YW_c - 1 downto 0);
        InRun      : std_logic;
        ErrFraming : std_logic;
        OutValid   : std_logic;
        OutData    : std_logic_vector(PixelBits_g - 1 downto 0);
        OutLast    : std_logic;
        OutUser    : std_logic_vector(1 downto 0);
        OutPosX    : unsigned(XW_c - 1 downto 0);
        OutPosY    : unsigned(YW_c - 1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- FS-1: first beat of a stream packet
    signal FirstBeat  : std_logic;
    signal InReadyInt : std_logic;
    signal StgInData  : std_logic_vector(StgWidth_c - 1 downto 0);
    signal StgValid   : std_logic;
    signal StgReady   : std_logic;
    signal StgData    : std_logic_vector(StgWidth_c - 1 downto 0);

    -- Loads the output register with a pixel at the given position (FS-3)
    procedure output (
        vr    : inout TwoProcess_r;
        pixel : std_logic_vector;
        x     : unsigned;
        y     : unsigned) is
    begin
        vr.OutValid := '1';
        vr.OutData  := pixel;
        vr.OutPosX  := x;
        vr.OutPosY  := y;
        if x >= LastX_c then
            vr.OutLast := '1';
        else
            vr.OutLast := '0';
        end if;
        if y = 0 and LastY_c = 0 then
            vr.OutUser := SeqOnly_c;
        elsif y = 0 then
            vr.OutUser := SeqFirst_c;
        elsif y >= LastY_c then
            vr.OutUser := SeqLast_c;
        else
            vr.OutUser := SeqCont_c;
        end if;
    end procedure;

    -- Moves the position to the next pixel of the image
    procedure advance (
        vr : inout TwoProcess_r) is
    begin
        if vr.PosX >= LastX_c then
            vr.PosX := (others => '0');
            vr.PosY := vr.PosY + 1;
        else
            vr.PosX := vr.PosX + 1;
        end if;
    end procedure;

begin

    assert ImageWidth_g <= 65536
        report "isp_frame_sync: ImageWidth_g must be 1 to 65536"
        severity failure;
    assert ImageHeight_g <= 65536
        report "isp_frame_sync: ImageHeight_g must be 1 to 65536"
        severity failure;
    assert PixelBits_g <= 64
        report "isp_frame_sync: PixelBits_g must be 1 to 64"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- FS-1 Input stage
    -----------------------------------------------------------------------------------------------
    p_first : process (Clk) is
    begin
        if rising_edge(Clk) then
            if In_Valid = '1' and InReadyInt = '1' then
                FirstBeat <= In_Last;
            end if;
            if Rst = '1' then
                FirstBeat <= '1';
            end if;
        end if;
    end process;

    StgInData <= In_Data & In_Last & In_User & FirstBeat;
    In_Ready  <= InReadyInt;

    i_stage : entity olo.olo_base_pl_stage
        generic map (
            Width_g    => StgWidth_c,
            Stages_g   => 1,
            UseReady_g => true
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Valid  => In_Valid,
            In_Ready  => InReadyInt,
            In_Data   => StgInData,
            Out_Valid => StgValid,
            Out_Ready => StgReady,
            Out_Data  => StgData
        );

    -----------------------------------------------------------------------------------------------
    -- FS-2 Image control and FS-3 Output register
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Pixel_v   : std_logic_vector(PixelBits_g - 1 downto 0);
        variable Last_v    : std_logic;
        variable User_v    : std_logic_vector(1 downto 0);
        variable First_v   : std_logic;
        variable Start_v   : boolean;
        variable EndFl_v   : boolean;
        variable OutFree_v : boolean;
        variable LastPx_v  : boolean;
    begin
        v            := r;
        v.ErrFraming := '0';

        -- Input stage word
        Pixel_v := StgData(StgWidth_c - 1 downto 4);
        Last_v  := StgData(3);
        User_v  := StgData(2 downto 1);
        First_v := StgData(0);
        Start_v := ispIsImageStart(First_v, User_v);
        -- The beat ends a packet with the flags "10" or "11"
        EndFl_v := Last_v = '1' and User_v(1) = '1';

        -- The output register is free when it is empty or read in this cycle
        OutFree_v := r.OutValid = '0' or Out_Ready = '1';
        if Out_Ready = '1' then
            v.OutValid := '0';
        end if;

        -- Pixel W x H - 1 of the open image
        LastPx_v := r.PosX >= LastX_c and r.PosY >= LastY_c;

        StgReady <= '0';

        case r.State is

            when Idle_s =>
                if StgValid = '1' then
                    if Start_v then
                        if OutFree_v then
                            StgReady <= '1';
                            v.InRun  := '0';
                            output(v, Pixel_v, to_unsigned(0, XW_c), to_unsigned(0, YW_c));
                            if OnePixel_c then
                                -- E3: the only pixel must end a packet with the flags "10" or "11"
                                if not EndFl_v then
                                    v.ErrFraming := '1';
                                end if;
                            else
                                -- E4: a packet with the last flags that ends at pixel 0
                                if EndFl_v then
                                    v.ErrFraming := '1';
                                end if;
                                v.PosX  := (others => '0');
                                v.PosY  := (others => '0');
                                advance(v);
                                v.State := Image_s;
                            end if;
                        end if;
                    else
                        -- E2: pixel without an image start, discarded whatever the output
                        StgReady <= '1';
                        if r.InRun = '0' then
                            v.ErrFraming := '1';
                            v.InRun      := '1';
                        end if;
                    end if;
                end if;

            when Image_s =>
                if StgValid = '1' then
                    if Start_v then
                        -- E1: the image start waits until the open image is complete
                        v.ErrFraming := '1';
                        v.State      := Pad_s;
                    elsif OutFree_v then
                        StgReady <= '1';
                        output(v, Pixel_v, r.PosX, r.PosY);
                        if LastPx_v then
                            -- E3: the last pixel must end a packet with the flags "10" or "11"
                            if not EndFl_v then
                                v.ErrFraming := '1';
                            end if;
                            v.PosX  := (others => '0');
                            v.PosY  := (others => '0');
                            v.InRun := '0';
                            v.State := Idle_s;
                        else
                            -- E4: a packet with the last flags that ends before the last pixel
                            if EndFl_v then
                                v.ErrFraming := '1';
                            end if;
                            advance(v);
                        end if;
                    end if;
                end if;

            when Pad_s =>
                if OutFree_v then
                    output(v, (PixelBits_g - 1 downto 0 => '0'), r.PosX, r.PosY);
                    if LastPx_v then
                        v.PosX  := (others => '0');
                        v.PosY  := (others => '0');
                        v.InRun := '0';
                        v.State := Idle_s;
                    else
                        advance(v);
                    end if;
                end if;

            when others =>
                v.PosX  := (others => '0');
                v.PosY  := (others => '0');
                v.State := Idle_s;

        end case;

        r_next <= v;
    end process;

    Out_Valid      <= r.OutValid;
    Out_Data       <= r.OutData;
    Out_Last       <= r.OutLast;
    Out_User       <= r.OutUser;
    Out_PosX       <= std_logic_vector(r.OutPosX);
    Out_PosY       <= std_logic_vector(r.OutPosY);
    Err_Framing    <= r.ErrFraming;
    Stat_ImageOpen <= '1' when r.State = Image_s or r.State = Pad_s else '0';

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State      <= Idle_s;
                r.PosX       <= (others => '0');
                r.PosY       <= (others => '0');
                r.InRun      <= '0';
                r.ErrFraming <= '0';
                r.OutValid   <= '0';
            end if;
        end if;
    end process;

end architecture;
