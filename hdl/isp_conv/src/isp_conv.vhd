---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Linear kernel of OpenISP: multiplies every element of a window by its signed coefficient and
-- outputs the sum as one pixel, 0 for a negative sum and saturated to OutBits_g. The coefficients
-- come from the generic Coef_g or, with RuntimeCoef_g, from registers on an AXI4-Lite slave, taken
-- with every image start (CTRL.HOLD keeps the set of the image before) and checked by one parity
-- bit per register; a coefficient with a wrong parity bit makes the image use the generic
-- (Err_Config), and so does a CTRL with a wrong parity bit as HOLD 0.
--
-- Documentation: hdl/isp_conv/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.isp_pkg.all;
    use work.isp_conv_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity isp_conv is
    generic (
        -- Bits per pixel of the window and the window (T = WinX_g x WinY_g elements)
        PixelBits_g   : positive;
        WinX_g        : positive := 3;
        WinY_g        : positive := 3;
        -- Coefficients: bits with the sign, the set (element 0 first), from the registers at run time
        CoefBits_g    : positive := 16;
        Coef_g        : integer_vector;
        RuntimeCoef_g : boolean  := false;
        -- Bits of the output pixel; 0 for the full precision
        OutBits_g     : natural  := 0
    );
    port (
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- Window stream: element k in bits (k + 1) x PixelBits_g - 1 downto k x PixelBits_g
        In_Valid          : in    std_logic;
        In_Ready          : out   std_logic;
        In_Data           : in    std_logic_vector(WinX_g * WinY_g * PixelBits_g - 1 downto 0);
        In_Last           : in    std_logic;
        In_User           : in    std_logic_vector(1 downto 0);
        -- Output pixel stream
        Out_Valid         : out   std_logic;
        Out_Ready         : in    std_logic;
        Out_Data          : out   std_logic_vector(ispConvOutBits(PixelBits_g, CoefBits_g, WinX_g * WinY_g,
                                                                  OutBits_g) - 1 downto 0);
        Out_Last          : out   std_logic;
        Out_User          : out   std_logic_vector(1 downto 0);
        -- AXI4-Lite slave of the registers (inactive when left open)
        S_AxiLite_ArAddr  : in    std_logic_vector(11 downto 0) := (others => '0');
        S_AxiLite_ArValid : in    std_logic                     := '0';
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(11 downto 0) := (others => '0');
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
        Err_Config        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of isp_conv is

    constant T_c  : positive := WinX_g * WinY_g;
    constant PB_c : positive := PixelBits_g;
    constant CB_c : positive := CoefBits_g;
    constant L_c  : natural  := log2ceil(T_c);
    -- Full precision F and the output width B (specification, section 1.1)
    constant F_c  : positive := ispConvFullBits(PB_c, CB_c, T_c);
    constant B_c  : positive := ispConvOutBits(PB_c, CB_c, T_c, OutBits_g);
    -- Width of the products and of the partial sums (signed, with room for every level)
    constant SW_c : positive := PB_c + CB_c + L_c + 1;

    type Coefs_t is array (0 to T_c - 1) of signed(CB_c - 1 downto 0);
    type Sums_t is array (0 to L_c, 0 to T_c - 1) of signed(SW_c - 1 downto 0);

    -- Valid (0), Last (1) and the sequence flags (3:2) of every stage: 0 input, 1 products, 2 to 1 + L levels,
    -- 2 + L output
    type Flags_t is array (0 to L_c + 2) of std_logic_vector(3 downto 0);

    -- The coefficient set of the generic, in the width of a coefficient
    function genCoefs return Coefs_t is
        variable C_v : Coefs_t;
    begin

        -- (a Coef_g of the wrong length reaches the check of CNV-CF-01 with its message)
        for k in 0 to T_c - 1 loop
            if k < Coef_g'length then
                C_v(k) := to_signed(Coef_g(Coef_g'low + k), CB_c);
            else
                C_v(k) := (others => '0');
            end if;
        end loop;

        return C_v;
    end function;

    function genParity return std_logic_vector is
        variable P_v : std_logic_vector(T_c - 1 downto 0);
    begin

        for k in 0 to T_c - 1 loop
            P_v(k) := xor std_logic_vector(genCoefs(k));
        end loop;

        return P_v;
    end function;

    constant GenCoefs_c  : Coefs_t                            := genCoefs;
    constant GenParity_c : std_logic_vector(T_c - 1 downto 0) := genParity;

    -- Largest output value 2^B - 1 in the width of the sums (the largest positive sum when B is wider)
    function outMax return signed is
        variable M_v : signed(SW_c - 1 downto 0) := (others => '0');
    begin

        for i in 0 to minimum(B_c, SW_c - 1) - 1 loop
            M_v(i) := '1';
        end loop;

        return M_v;
    end function;

    constant OutMax_c : signed(SW_c - 1 downto 0) := outMax;

    type TwoProcess_r is record
        -- Registers (CV-4)
        Coef      : Coefs_t;
        Parity    : std_logic_vector(T_c - 1 downto 0);
        Hold      : std_logic;
        CtrlPar   : std_logic;
        FlagCfg   : std_logic;
        RdValid   : std_logic;
        RdData    : std_logic_vector(31 downto 0);
        -- Working coefficient set (CV-1) and the image start detection
        Work      : Coefs_t;
        First     : std_logic;
        ErrConfig : std_logic;
        -- Pipeline (section 4)
        Win       : std_logic_vector(T_c * PB_c - 1 downto 0);
        Sums      : Sums_t;
        OutData   : std_logic_vector(B_c - 1 downto 0);
        Flags     : Flags_t;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Register bus of the AXI4-Lite slave
    signal Rb_Addr    : std_logic_vector(11 downto 0);
    signal Rb_Wr      : std_logic;
    signal Rb_ByteEna : std_logic_vector(3 downto 0);
    signal Rb_WrData  : std_logic_vector(31 downto 0);
    signal Rb_Rd      : std_logic;

begin

    -- CNV-CF-01: the generics outside their range stop the elaboration
    assert PixelBits_g <= 32
        report "isp_conv: PixelBits_g must be 1 to 32"
        severity failure;
    assert WinX_g <= 16
        report "isp_conv: WinX_g must be 1 to 16"
        severity failure;
    assert WinY_g <= 16
        report "isp_conv: WinY_g must be 1 to 16"
        severity failure;
    assert CoefBits_g >= 2 and CoefBits_g <= 18
        report "isp_conv: CoefBits_g must be 2 to 18"
        severity failure;
    assert OutBits_g <= 64
        report "isp_conv: OutBits_g must be 0 or 1 to 64"
        severity failure;
    assert Coef_g'length = WinX_g * WinY_g
        report "isp_conv: Coef_g must have WinX_g x WinY_g values"
        severity failure;

    g_coef_range : for k in 0 to WinX_g * WinY_g - 1 generate
        assert Coef_g'length /= WinX_g * WinY_g or
               (Coef_g(Coef_g'low + k) >= -2 ** (CoefBits_g - 1) and Coef_g(Coef_g'low + k) <= 2 ** (CoefBits_g - 1) - 1)
            report "isp_conv: Coef_g values must be -2^(CoefBits_g - 1) to 2^(CoefBits_g - 1) - 1"
            severity failure;
    end generate;

    -----------------------------------------------------------------------------------------------
    -- CV-4 AXI4-Lite slave
    -----------------------------------------------------------------------------------------------
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g => 12,
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
    -- CV-1 to CV-3 Pipeline, CV-4 Registers
    -----------------------------------------------------------------------------------------------
    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable Advance_v : boolean;
        variable Start_v   : boolean;
        variable CtrlBad_v : boolean;
        variable ParOk_v   : boolean;
        variable N_v       : natural;
        variable Elem_v    : signed(PB_c downto 0);
        variable Sum_v     : signed(SW_c - 1 downto 0);
        variable Word_v    : std_logic_vector(31 downto 0);
        variable K_v       : natural;
        variable Addr_v    : natural;
        variable ClrCfg_v  : boolean;
    begin
        v           := r;
        v.ErrConfig := '0';

        -- All stages advance together when the output register is empty or its beat transfers
        Advance_v := r.Flags(L_c + 2)(0) = '0' or Out_Ready = '1';
        if Advance_v then
            In_Ready <= '1';
        else
            In_Ready <= '0';
        end if;

        if Advance_v then
            -- CV-3: output register, 0 for a negative sum, saturation to B bits
            Sum_v := r.Sums(L_c, 0);
            if Sum_v < 0 then
                v.OutData := (others => '0');
            elsif Sum_v > OutMax_c then
                v.OutData := (others => '1');
            else
                v.OutData := std_logic_vector(resize(unsigned(Sum_v), B_c));
            end if;

            -- CV-2: adder tree, one level per stage; an odd element passes on
            for l in L_c downto 1 loop
                N_v := (T_c + 2 ** (l - 1) - 1) / 2 ** (l - 1);

                for i in 0 to T_c - 1 loop
                    if 2 * i + 1 < N_v then
                        v.Sums(l, i) := r.Sums(l - 1, 2 * i) + r.Sums(l - 1, 2 * i + 1);
                    elsif 2 * i < N_v then
                        v.Sums(l, i) := r.Sums(l - 1, 2 * i);
                    end if;
                end loop;

            end loop;

            -- CV-1: products of the window of stage 1 with the working set
            for k in 0 to T_c - 1 loop
                Elem_v       := signed('0' & r.Win((k + 1) * PB_c - 1 downto k * PB_c));
                v.Sums(0, k) := resize(Elem_v * r.Work(k), SW_c);
            end loop;

            for s in L_c + 2 downto 1 loop
                v.Flags(s) := r.Flags(s - 1);
            end loop;

            -- Stage 1: the window; the image start loads the working set (CNV-FN-04, CNV-ER-01)
            v.Flags(0)(0) := In_Valid;
            if In_Valid = '1' then
                v.Win                  := In_Data;
                v.Flags(0)(1)          := In_Last;
                v.Flags(0)(3 downto 2) := In_User;
                v.First                := In_Last;
                Start_v                := ispIsImageStart(r.First, In_User);
                CtrlBad_v              := r.Hold /= r.CtrlPar;
                if RuntimeCoef_g and Start_v and CtrlBad_v then
                    v.ErrConfig := '1';
                end if;
                if RuntimeCoef_g and Start_v and (r.Hold = '0' or CtrlBad_v) then
                    ParOk_v := true;

                    for k in 0 to T_c - 1 loop
                        if (xor std_logic_vector(r.Coef(k))) /= r.Parity(k) then
                            ParOk_v := false;
                        end if;
                    end loop;

                    if ParOk_v then
                        v.Work := r.Coef;
                    else
                        v.Work      := GenCoefs_c;
                        v.ErrConfig := '1';
                    end if;
                end if;
            end if;
        end if;

        -- CV-4: register writes
        ClrCfg_v := false;
        Addr_v   := to_integer(unsigned(Rb_Addr));
        if Rb_Wr = '1' then
            if Addr_v = RegCtrl_c and Rb_ByteEna(0) = '1' then
                v.Hold    := Rb_WrData(CtrlHold_c);
                v.CtrlPar := Rb_WrData(CtrlHold_c);
            elsif Addr_v = RegStatus_c and Rb_ByteEna(1) = '1' then
                ClrCfg_v := Rb_WrData(StatusErrConfig_c) = '1';
            elsif Addr_v = RegInject_c and RuntimeCoef_g and Rb_ByteEna(0) = '1' then
                -- INDEX of the same write; 0 when its byte is not written
                K_v := 0;
                if Rb_ByteEna(1) = '1' then
                    K_v := to_integer(unsigned(Rb_WrData(InjectIndexHi_c downto InjectIndexLo_c)));
                end if;

                -- One compare per coefficient: the parity bit k depends on its own bit and the index only
                for k in 0 to T_c - 1 loop
                    if Rb_WrData(InjectParity_c) = '1' and K_v = k then
                        v.Parity(k) := not r.Parity(k);
                    end if;
                end loop;

                if Rb_WrData(InjectCtrlParity_c) = '1' then
                    v.CtrlPar := not r.CtrlPar;
                end if;
            elsif RuntimeCoef_g and Addr_v >= RegCoef_c and Addr_v < RegCoef_c + RegCoefStride_c * T_c then
                -- One address compare per coefficient: coefficient k and its parity bit depend on their own register,
                -- not on a selection among all coefficients

                for k in 0 to T_c - 1 loop
                    if Addr_v = RegCoef_c + RegCoefStride_c * k then
                        Word_v := std_logic_vector(resize(r.Coef(k), 32));

                        for b in 0 to 3 loop
                            if Rb_ByteEna(b) = '1' then
                                Word_v(8 * b + 7 downto 8 * b) := Rb_WrData(8 * b + 7 downto 8 * b);
                            end if;
                        end loop;

                        -- The bits above CoefBits_g are not stored; every write sets the parity bit (CNV-RG-03)
                        v.Coef(k)   := signed(Word_v(CB_c - 1 downto 0));
                        v.Parity(k) := xor Word_v(CB_c - 1 downto 0);
                    end if;
                end loop;

            end if;
        end if;

        -- Sticky flag: the event wins over a clear in the same cycle (CNV-RG-02)
        if ClrCfg_v then
            v.FlagCfg := '0';
        end if;
        if r.ErrConfig = '1' then
            v.FlagCfg := '1';
        end if;

        -- CV-4: register reads, answered in the next cycle
        v.RdValid := '0';
        if Rb_Rd = '1' then
            v.RdValid := '1';
            v.RdData  := (others => '0');
            if Addr_v = RegId_c then
                v.RdData := RegMapId_c;
            elsif Addr_v = RegParam_c then
                v.RdData(ParamWinXHi_c downto ParamWinXLo_c)           := std_logic_vector(to_unsigned(WinX_g, 5));
                v.RdData(ParamWinYHi_c downto ParamWinYLo_c)           := std_logic_vector(to_unsigned(WinY_g, 5));
                v.RdData(ParamCoefBitsHi_c downto ParamCoefBitsLo_c)   := std_logic_vector(to_unsigned(CB_c, 5));
                v.RdData(ParamPixelBitsHi_c downto ParamPixelBitsLo_c) := std_logic_vector(to_unsigned(PB_c, 6));
            elsif Addr_v = RegCtrl_c then
                v.RdData(CtrlHold_c) := r.Hold;
            elsif Addr_v = RegStatus_c then
                v.RdData(StatusErrConfig_c) := r.FlagCfg;
            elsif Addr_v >= RegCoef_c and Addr_v < RegCoef_c + RegCoefStride_c * T_c and
                  (Addr_v - RegCoef_c) mod RegCoefStride_c = 0 then
                -- Sign-extended to 32 bits
                v.RdData := std_logic_vector(resize(r.Coef((Addr_v - RegCoef_c) / RegCoefStride_c), 32));
            end if;
        end if;

        -- With RuntimeCoef_g false the coefficients and the working set are the generic
        if not RuntimeCoef_g then
            v.Coef   := GenCoefs_c;
            v.Parity := GenParity_c;
            v.Work   := GenCoefs_c;
        end if;

        r_next <= v;
    end process;

    Out_Valid  <= r.Flags(L_c + 2)(0);
    Out_Data   <= r.OutData;
    Out_Last   <= r.Flags(L_c + 2)(1);
    Out_User   <= r.Flags(L_c + 2)(3 downto 2);
    Err_Config <= r.ErrConfig;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Coef      <= GenCoefs_c;
                r.Parity    <= GenParity_c;
                r.Hold      <= '0';
                r.CtrlPar   <= '0';
                r.FlagCfg   <= '0';
                r.RdValid   <= '0';
                r.Work      <= GenCoefs_c;
                r.First     <= '1';
                r.ErrConfig <= '0';
                r.Flags     <= (others => (others => '0'));
            end if;
        end if;
    end process;

end architecture;
