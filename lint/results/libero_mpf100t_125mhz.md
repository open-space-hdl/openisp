# Preliminary synthesis on PolarFire MPF100T at 125 MHz

Results of `python lint/libero_synth.py` (Libero SoC, Synplify Pro, MPF100T FCG484, speed grade STD, block flow,
a clock of 125 MHz on `Clk`) for the configurations of `lint/vivado_ooc.py`. These are pre-layout estimates of the
synthesis on PolarFire MPF100T: not a timing closure, and not on the reference device. Only register-to-register paths
are constrained.

Columns: worst slack and estimated frequency of `Clk`; resources (4LUT and DFF including the interface logic of the
RAM and Math blocks); the worst path with its logic levels and its estimated route share.

| Configuration | Slack (ns) | MHz | 4LUT | DFF | LSRAM | uSRAM | Math | Levels | Route (%) | Worst path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fsy_max | 2.174 | 171.6 | 204 | 276 | 0 | 0 | 0 | 4 | 86.8 | `r.OutValid` -> `i_stage.g_nonzero.g_stages.0.i_stg.r.DataShad[0]` |
| crp_default | 2.854 | 194.3 | 430 | 367 | 0 | 0 | 0 | 16 | 76.3 | `r.PosY[0]` -> `i_frame_sync.r.OutPosX[0]` |
| pnt_default | 2.142 | 170.7 | 942 | 597 | 0 | 0 | 1 | 5 | 84.4 | `r.PFlags_5_3[0]` -> `i_frame_sync.i_stage.g_nonzero.g_stages.0.i_stg.r.DataShadVld` |
| pnt_wide | -4.402 | 80.6 | 2343 | 2076 | 0 | 0 | 8 | 36 | 32.5 | `r.Sum_mod[0]` -> `r.Prod_1_0[83]` |
| win_default | 0.950 | 141.8 | 1118 | 724 | 8 | 0 | 0 | 6 | 84.0 | `r.State[1]` -> `r.Win_1_0[10]` |
| win_mirror5 | -0.300 | 120.5 | 2292 | 1683 | 20 | 0 | 0 | 10 | 79.2 | `r.State[1]` -> `r.Win_0_0[0]` |
| win_max | -1.489 | 105.4 | 10956 | 14977 | 120 | 0 | 0 | 20 | 71.2 | `r.OutValid` -> `r.RowSel_6[0]` |
| cnv_mtf3 | 0.443 | 132.3 | 1093 | 1042 | 0 | 0 | 9 | 8 | 74.1 | `i_axi.r.Addr[8]` -> `r.Parity[0]` |
| cnv_mtf5 | -0.039 | 124.4 | 2792 | 2470 | 0 | 0 | 25 | 11 | 69.1 | `i_axi.r.Addr_fast[8]` -> `r.Parity[2]` |
| cnv_max | -4.600 | 79.4 | 21930 | 33512 | 0 | 0 | 256 | 18 | 69.8 | `i_axi.r.Addr[11]` -> `r.Parity[13]` |
| cnv_bin4 | 4.362 | 274.9 | 108 | 214 | 0 | 0 | 0 | 2 | 86.2 | `r.Flags_4_3[0]` -> `r.Flags_0[0]` |
| flt_mtf5 | -1.258 | 108.0 | 4687 | 3833 | 16 | 0 | 25 | 12 | 73.4 | `i_conv.i_axi.r.Addr[9]` -> `i_conv.r.Parity[2]` |
| bin_default | 1.857 | 162.8 | 610 | 622 | 2 | 0 | 0 | 4 | 66.3 | `g_vertical.i_vertical.i_conv.r.Flags_3_2[0]` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| bin_4x4_rep | 1.474 | 153.2 | 1489 | 1108 | 3 | 0 | 0 | 4 | 76.3 | `g_vertical.i_vertical.i_window.r.State[0]` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| rpl_default | -2.622 | 94.1 | 7340 | 6572 | 156 | 0 | 2 | 10 | 46.6 | `i_map.i_ram_sdp.i_ram.g_nobe.i_ram.mem_v_mem_v_2_31` -> `r.Queue_2[1]` |
| rpl_g7 | -1.162 | 109.1 | 9641 | 7359 | 156 | 0 | 9 | 7 | 40.4 | `i_map.i_ram_sdp.i_ram.g_nobe.i_ram.mem_v_mem_v_2_15` -> `r.Queue_0[1]` |
