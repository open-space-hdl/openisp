# Preliminary synthesis on PolarFire MPF100T at 150 MHz

Results of `python lint/libero_synth.py` (Libero SoC, Synplify Pro, MPF100T FCG484, speed grade STD, block flow,
a clock of 150 MHz on `Clk`) for the configurations of `lint/vivado_ooc.py`. These are pre-layout estimates of the
synthesis on PolarFire MPF100T: not a timing closure, and not on the reference device. Only register-to-register paths
are constrained.

Columns: worst slack and estimated frequency of `Clk`; resources (4LUT and DFF including the interface logic of the
RAM and Math blocks); the worst path with its logic levels and its estimated route share.

| Configuration | Slack (ns) | MHz | 4LUT | DFF | LSRAM | uSRAM | Math | Levels | Route (%) | Worst path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| fsy_max | 1.299 | 186.3 | 207 | 276 | 0 | 0 | 0 | 5 | 78.7 | `r.State[1]` -> `r.PosX[0]` |
| crp_default | 2.020 | 215.2 | 432 | 367 | 0 | 0 | 0 | 16 | 72.2 | `r.PosY[0]` -> `i_frame_sync.r.OutPosX[0]` |
| pnt_default | 0.696 | 167.5 | 948 | 597 | 0 | 0 | 1 | 5 | 84.7 | `r.PFlags_5_3[0]` -> `i_frame_sync.i_stage.g_nonzero.g_stages.0.i_stg.r.DataShadVld` |
| pnt_wide | -5.735 | 80.6 | 2343 | 2076 | 0 | 0 | 8 | 36 | 32.5 | `r.Sum_mod[0]` -> `r.Prod_1_0[83]` |
| win_default | -0.006 | 149.9 | 1134 | 724 | 8 | 0 | 0 | 5 | 84.0 | `r.State[0]` -> `r.Win_1_0[11]` |
| win_mirror5 | -1.453 | 123.2 | 2284 | 1683 | 20 | 0 | 0 | 11 | 79.7 | `r.State[0]` -> `r.Win_0_0[0]` |
| win_max | -4.224 | 91.8 | 11241 | 14984 | 120 | 0 | 0 | 13 | 73.9 | `r.OutValid_fast` -> `r.EccSec` |
| cnv_mtf3 | -0.914 | 131.9 | 1104 | 1042 | 0 | 0 | 9 | 8 | 74.2 | `i_axi.r.Addr[8]` -> `r.Parity[0]` |
| cnv_mtf5 | -1.372 | 124.4 | 2795 | 2470 | 0 | 0 | 25 | 11 | 69.1 | `i_axi.r.Addr_fast[8]` -> `r.Parity[2]` |
| cnv_max | -5.933 | 79.4 | 21930 | 33512 | 0 | 0 | 256 | 18 | 69.8 | `i_axi.r.Addr[11]` -> `r.Parity[13]` |
| cnv_bin4 | 3.030 | 274.9 | 109 | 214 | 0 | 0 | 0 | 2 | 86.2 | `r.Flags_4_3[0]` -> `r.Flags_0[0]` |
| flt_mtf5 | -2.549 | 108.5 | 4698 | 3833 | 16 | 0 | 25 | 12 | 79.8 | `i_window.r.State[0]` -> `i_window.r.Win_0_0[0]` |
| bin_default | 0.809 | 170.7 | 613 | 622 | 2 | 0 | 0 | 4 | 61.0 | `g_vertical.i_vertical.i_conv.r.Flags_3_2[0]` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| bin_4x4_rep | 0.252 | 155.9 | 1524 | 1128 | 3 | 0 | 0 | 6 | 63.2 | `g_vertical.i_vertical.i_window.r.State[0]` -> `g_vertical.i_vertical.i_window.g_delays.1.i_delay.i_delay.g_bram.i_bram.g_nobe.i_ram.mem_v_mem_v_0_0` |
| rpl_default | -4.578 | 88.9 | 7361 | 6572 | 156 | 0 | 2 | 11 | 47.4 | `i_map.i_ram_sdp.i_ram.g_nobe.i_ram.mem_v_mem_v_2_20` -> `r.Queue_0[4]` |
| rpl_g7 | -2.449 | 109.7 | 9852 | 7358 | 156 | 0 | 9 | 7 | 44.9 | `i_map.i_ram_sdp.i_ram.g_nobe.i_ram.mem_v_mem_v_2_31` -> `r.Queue_2[20]` |
