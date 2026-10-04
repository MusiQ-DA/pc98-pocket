// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_ram_dma_fill.h for the primary calling header

#include "Vtb_ram_dma_fill__pch.h"
#include "Vtb_ram_dma_fill___024root.h"

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_static__TOP(Vtb_ram_dma_fill___024root* vlSelf);

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_static(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_static\n"); );
    // Body
    Vtb_ram_dma_fill___024root___eval_static__TOP(vlSelf);
}

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_static__TOP(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_static__TOP\n"); );
    // Body
    vlSelf->tb_ram_dma_fill__DOT__clk = 0U;
    vlSelf->tb_ram_dma_fill__DOT__reset = 1U;
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n = 1U;
    vlSelf->tb_ram_dma_fill__DOT__bench_addr = 0U;
    vlSelf->tb_ram_dma_fill__DOT__clipw = 0U;
    vlSelf->tb_ram_dma_fill__DOT__clip_cnt = 0U;
    vlSelf->tb_ram_dma_fill__DOT__clip_active = 0U;
    vlSelf->tb_ram_dma_fill__DOT__hlda = 0U;
    vlSelf->tb_ram_dma_fill__DOT__aen_n = 1U;
    vlSelf->tb_ram_dma_fill__DOT__dma_wait = 0U;
    vlSelf->tb_ram_dma_fill__DOT__want_drq = 0U;
    vlSelf->tb_ram_dma_fill__DOT__p1_flag = 0U;
    vlSelf->tb_ram_dma_fill__DOT__p1_at = 0xffffffffU;
    vlSelf->tb_ram_dma_fill__DOT__p1_len = 8U;
    vlSelf->tb_ram_dma_fill__DOT__p1_tick = 0U;
    vlSelf->tb_ram_dma_fill__DOT__dreq = 0U;
    vlSelf->tb_ram_dma_fill__DOT__gv_req = 0U;
    vlSelf->tb_ram_dma_fill__DOT__gv_timer = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ri_req = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ri_addr = 0x620000U;
    vlSelf->tb_ram_dma_fill__DOT__fgn_rd = 0U;
    vlSelf->tb_ram_dma_fill__DOT__fgn_timer = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ems98_unused[0U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ems98_unused[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ems98_unused[2U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__ems98_unused[3U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__memw_pulses = 0U;
    vlSelf->tb_ram_dma_fill__DOT__wc_seen = 0U;
    vlSelf->tb_ram_dma_fill__DOT__wr_accept = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr_writes = 0U;
    vlSelf->tb_ram_dma_fill__DOT__tail_trace = 0U;
    vlSelf->tb_ram_dma_fill__DOT__acc_prev = 0U;
    vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_d = 1U;
    vlSelf->tb_ram_dma_fill__DOT__errors = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select[0U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select[1U] = 1U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select[2U] = 2U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select[3U] = 3U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select[0U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select[1U] = 1U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select[2U] = 2U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select[3U] = 3U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd = 0U;
}

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_initial__TOP(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_initial__TOP\n"); );
    // Body
    if ((! VL_VALUEPLUSARGS_INI(32, std::string{"dbgrd=%d"}, 
                                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd))) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd = 0U;
    }
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[0U] = 0xffffffffU;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[0U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[0U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[0U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[1U] = 0xffffffffU;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[1U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[1U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[1U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[2U] = 0xffffffffU;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[2U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[2U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[2U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[3U] = 0xffffffffU;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[3U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[3U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[3U] = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_at = 0xfffffc18U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_count = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat = 3U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__reads_served = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__writes_served = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[0U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[2U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[3U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[4U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[5U] = 0U;
}

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_final(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_final\n"); );
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__stl(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vtb_ram_dma_fill___024root___eval_phase__stl(Vtb_ram_dma_fill___024root* vlSelf);

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_settle(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_settle\n"); );
    // Init
    IData/*31:0*/ __VstlIterCount;
    CData/*0:0*/ __VstlContinue;
    // Body
    __VstlIterCount = 0U;
    vlSelf->__VstlFirstIteration = 1U;
    __VstlContinue = 1U;
    while (__VstlContinue) {
        if (VL_UNLIKELY((0x64U < __VstlIterCount))) {
#ifdef VL_DEBUG
            Vtb_ram_dma_fill___024root___dump_triggers__stl(vlSelf);
#endif
            VL_FATAL_MT("/work/sim/tb_ram_dma_fill.sv", 32, "", "Settle region did not converge.");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        __VstlContinue = 0U;
        if (Vtb_ram_dma_fill___024root___eval_phase__stl(vlSelf)) {
            __VstlContinue = 1U;
        }
        vlSelf->__VstlFirstIteration = 0U;
    }
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__stl(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VstlTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VstlTriggered.word(0U))) {
        VL_DBG_MSGF("         'stl' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
    if ((2ULL & vlSelf->__VstlTriggered.word(0U))) {
        VL_DBG_MSGF("         'stl' region trigger index 1 is active: @([hybrid] tb_ram_dma_fill.u_ce.cpu_edge_num)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___stl_sequent__TOP__0(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___stl_sequent__TOP__0\n"); );
    // Init
    CData/*0:0*/ tb_ram_dma_fill__DOT__ram_address_select_n;
    tb_ram_dma_fill__DOT__ram_address_select_n = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win;
    tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__idle;
    tb_ram_dma_fill__DOT__u_ram__DOT__idle = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match;
    tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__read_strobe_match;
    tb_ram_dma_fill__DOT__u_ram__DOT__read_strobe_match = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__parked_match;
    tb_ram_dma_fill__DOT__u_ram__DOT__parked_match = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__parked2_match;
    tb_ram_dma_fill__DOT__u_ram__DOT__parked2_match = 0;
    SData/*10:0*/ tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0;
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0 = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h1f356822__0;
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h1f356822__0 = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h3d9a9fa7__0;
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h3d9a9fa7__0 = 0;
    IData/*31:0*/ tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx;
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx = 0;
    CData/*0:0*/ __VdfgTmp_h82709370__0;
    __VdfgTmp_h82709370__0 = 0;
    CData/*3:0*/ __Vfunc_resolv_priority__13__Vfuncout;
    __Vfunc_resolv_priority__13__Vfuncout = 0;
    CData/*3:0*/ __Vfunc_resolv_priority__13__request;
    __Vfunc_resolv_priority__13__request = 0;
    CData/*1:0*/ __Vfunc_bit2num__15__Vfuncout;
    __Vfunc_bit2num__15__Vfuncout = 0;
    CData/*3:0*/ __Vfunc_bit2num__15__source;
    __Vfunc_bit2num__15__source = 0;
    CData/*1:0*/ __Vfunc_bit2num__16__Vfuncout;
    __Vfunc_bit2num__16__Vfuncout = 0;
    CData/*3:0*/ __Vfunc_bit2num__16__source;
    __Vfunc_bit2num__16__source = 0;
    CData/*31:0*/ __Vtemp_6;
    CData/*31:0*/ __Vtemp_7;
    // Body
    vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait = 0U;
    if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den 
            = ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
                ? 1U : 0xc9U);
        vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait = 1U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den = 0xc9U;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable 
        = ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable)) 
           | ((vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
               [2U] << 2U) | ((vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                               [1U] << 1U) | vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                              [0U])));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable 
        = ((7U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable)) 
           | (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
              [3U] << 3U));
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__speed_change 
        = (0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request 
        = ((((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
              [3U]) | (2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                       [3U])) << 3U) | ((((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                           [2U]) | 
                                          (2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                           [2U])) << 2U) 
                                        | ((((1U == 
                                              vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                              [1U]) 
                                             | (2U 
                                                == 
                                                vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                                [1U])) 
                                            << 1U) 
                                           | ((1U == 
                                               vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                               [0U]) 
                                              | (2U 
                                                 == 
                                                 vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                                 [0U])))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_due 
        = (0x140U <= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank 
        = (3U & (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
                 >> 9U));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[0U] 
        = ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt))
            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_r)
            : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_hi_r));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[2U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold1 = 
        (VL_GTES_III(32, 5U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat) 
         & ((5U >= (7U & vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat)) 
            && vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
            [(7U & vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat)]));
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold2 = 
        (VL_GTES_III(32, 5U, ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat)) 
         & ((5U >= (7U & ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat))) 
            && vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
            [(7U & ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat))]));
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT____VdfgTmp_h854dc19a__0 
        = (VL_LTES_III(32, 1U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat) 
           & ((5U >= (7U & (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat 
                            - (IData)(1U)))) && vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
              [(7U & (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat 
                      - (IData)(1U)))]));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control 
        = ((0U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
           && ((1U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
               && ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                   || ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                       || ((4U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                           || ((5U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                               || (6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)))))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy));
    vlSelf->tb_ram_dma_fill__DOT__dma_ready = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait)) 
                                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait_Qn));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[0U] 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__addr_r;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[2U] = 0xa00000U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[3U] 
        = (0xffffffU & vlSelf->tb_ram_dma_fill__DOT__ri_addr);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req 
        = (((IData)(vlSelf->tb_ram_dma_fill__DOT__ri_req) 
            << 4U) | (((IData)(vlSelf->tb_ram_dma_fill__DOT__gv_req) 
                       << 3U) | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req)));
    vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n = ((IData)(vlSelf->tb_ram_dma_fill__DOT__bench_iow_n) 
                                                   & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n));
    __Vfunc_bit2num__16__source = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal;
    __Vfunc_bit2num__16__Vfuncout = ((1U & (IData)(__Vfunc_bit2num__16__source))
                                      ? 0U : ((2U & (IData)(__Vfunc_bit2num__16__source))
                                               ? 1U
                                               : ((4U 
                                                   & (IData)(__Vfunc_bit2num__16__source))
                                                   ? 2U
                                                   : 
                                                  ((8U 
                                                    & (IData)(__Vfunc_bit2num__16__source))
                                                    ? 3U
                                                    : 0U))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select 
        = __Vfunc_bit2num__16__Vfuncout;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state) 
           & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state) 
           & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state) 
           | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select 
        = ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
            ? 0U : ((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                     ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                     : ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                         ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                         : ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                             ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                             : ((4U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                                 ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                                 : ((5U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                                     ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                                     : ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                                         ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                                         : 0U)))))));
    if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data_hi;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((1U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word)
                ? 2U : 1U);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((2U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word)
                ? 2U : 1U);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((4U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 0U;
    } else if ((6U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_udqm = 1U;
        vlSelf->tb_ram_dma_fill__DOT__s_ldqm = 1U;
    }
    __Vtemp_6 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority)
                  ? ([&]() {
                vlSelf->__Vfunc_rotate_right__12__rotate 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate;
                vlSelf->__Vfunc_rotate_right__12__source 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma;
                vlSelf->__Vfunc_rotate_right__12__Vfuncout 
                    = ((2U & (IData)(vlSelf->__Vfunc_rotate_right__12__rotate))
                        ? ((1U & (IData)(vlSelf->__Vfunc_rotate_right__12__rotate))
                            ? (IData)(vlSelf->__Vfunc_rotate_right__12__source)
                            : ((0xeU & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                        << 1U)) | (1U 
                                                   & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                                      >> 3U))))
                        : ((1U & (IData)(vlSelf->__Vfunc_rotate_right__12__rotate))
                            ? ((0xcU & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                        << 2U)) | (3U 
                                                   & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                                      >> 2U)))
                            : ((8U & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                      << 3U)) | (7U 
                                                 & ((IData)(vlSelf->__Vfunc_rotate_right__12__source) 
                                                    >> 1U)))));
            }(), (IData)(vlSelf->__Vfunc_rotate_right__12__Vfuncout))
                  : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = __Vtemp_6;
    __Vfunc_resolv_priority__13__request = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma;
    __Vfunc_resolv_priority__13__Vfuncout = ((1U & (IData)(__Vfunc_resolv_priority__13__request))
                                              ? 1U : 
                                             ((2U & (IData)(__Vfunc_resolv_priority__13__request))
                                               ? 2U
                                               : ((4U 
                                                   & (IData)(__Vfunc_resolv_priority__13__request))
                                                   ? 4U
                                                   : 
                                                  ((8U 
                                                    & (IData)(__Vfunc_resolv_priority__13__request))
                                                    ? 8U
                                                    : 0U))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = __Vfunc_resolv_priority__13__Vfuncout;
    __Vtemp_7 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority)
                  ? ([&]() {
                vlSelf->__Vfunc_rotate_left__14__rotate 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate;
                vlSelf->__Vfunc_rotate_left__14__source 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma;
                vlSelf->__Vfunc_rotate_left__14__Vfuncout 
                    = ((2U & (IData)(vlSelf->__Vfunc_rotate_left__14__rotate))
                        ? ((1U & (IData)(vlSelf->__Vfunc_rotate_left__14__rotate))
                            ? (IData)(vlSelf->__Vfunc_rotate_left__14__source)
                            : ((8U & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                      << 3U)) | (7U 
                                                 & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                                    >> 1U))))
                        : ((1U & (IData)(vlSelf->__Vfunc_rotate_left__14__rotate))
                            ? ((0xcU & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                        << 2U)) | (3U 
                                                   & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                                      >> 2U)))
                            : ((0xeU & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                        << 1U)) | (1U 
                                                   & ((IData)(vlSelf->__Vfunc_rotate_left__14__source) 
                                                      >> 3U)))));
            }(), (IData)(vlSelf->__Vfunc_rotate_left__14__Vfuncout))
                  : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = __Vtemp_7;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__controller_disable)
            ? 0U : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma));
    __VdfgTmp_h82709370__0 = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n)) 
                                    | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n)) 
                                       & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0 
        = (1U & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__clip_active) 
                    | (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n))));
    vlSelf->tb_ram_dma_fill__DOT__dack_n = (0xfU & 
                                            ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dack_sense_active_high)
                                              ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff)
                                              : (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff))));
    vlSelf->tb_ram_dma_fill__DOT____Vcellinp__sdr__dqm 
        = (((IData)(vlSelf->tb_ram_dma_fill__DOT__s_udqm) 
            << 1U) | (IData)(vlSelf->tb_ram_dma_fill__DOT__s_ldqm));
    vlSelf->tb_ram_dma_fill__DOT__dq_in__en0 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT____VdfgTmp_h854dc19a__0)
                                                 ? 0xffffU
                                                 : 
                                                ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold1)
                                                  ? 0xffffU
                                                  : 
                                                 ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold2)
                                                   ? 0xffffU
                                                   : 0U)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n) 
                       | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control)))));
    __Vfunc_bit2num__15__source = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select;
    __Vfunc_bit2num__15__Vfuncout = ((1U & (IData)(__Vfunc_bit2num__15__source))
                                      ? 0U : ((2U & (IData)(__Vfunc_bit2num__15__source))
                                               ? 1U
                                               : ((4U 
                                                   & (IData)(__Vfunc_bit2num__15__source))
                                                   ? 2U
                                                   : 
                                                  ((8U 
                                                    & (IData)(__Vfunc_bit2num__15__source))
                                                    ? 3U
                                                    : 0U))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__dma_select 
        = __Vfunc_bit2num__15__Vfuncout;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 0U;
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx 
        = VL_MODDIV_III(32, ((IData)(4U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr)), (IData)(5U));
    if (((4U >= (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx)) 
         && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req) 
                   >> (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx))))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner 
            = (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 1U;
    }
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx 
        = VL_MODDIV_III(32, ((IData)(3U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr)), (IData)(5U));
    if (((4U >= (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx)) 
         && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req) 
                   >> (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx))))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner 
            = (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 1U;
    }
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx 
        = VL_MODDIV_III(32, ((IData)(2U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr)), (IData)(5U));
    if (((4U >= (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx)) 
         && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req) 
                   >> (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx))))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner 
            = (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 1U;
    }
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx 
        = VL_MODDIV_III(32, ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr)), (IData)(5U));
    if (((4U >= (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx)) 
         && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req) 
                   >> (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx))))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner 
            = (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 1U;
    }
    tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx 
        = VL_MODDIV_III(32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr), (IData)(5U));
    if (((4U >= (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx)) 
         && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req) 
                   >> (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx))))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner 
            = (7U & tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__idx);
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = 1U;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__prev_write_enable_n)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register 
        = ((0U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
           && ((1U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
               && ((2U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                   && ((3U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                       && ((4U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                           && ((5U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                               && ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                   && (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                                       [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select] 
                                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal)))))))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = 0U;
    if ((0U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if ((1U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
            if ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
                if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                     [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])) {
                    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = 1U;
                }
            } else if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing) {
                    if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                         [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])) {
                        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = 1U;
                    }
                }
            } else if ((4U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
                if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                     [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])) {
                    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = 1U;
                }
            } else if ((5U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
                vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = 1U;
            }
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state;
    if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma))) {
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 1U;
        }
    } else if ((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if (vlSelf->tb_ram_dma_fill__DOT__hlda) {
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 2U;
        }
    } else if ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state 
            = ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])
                ? 6U : 3U);
    } else if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing) {
            if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                 [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])) {
                if (vlSelf->tb_ram_dma_fill__DOT__dma_ready) {
                    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 6U;
                }
            } else {
                vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 5U;
            }
        } else {
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 4U;
        }
    } else if ((4U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
             [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])) {
            if (vlSelf->tb_ram_dma_fill__DOT__dma_ready) {
                vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 6U;
            }
        } else {
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 5U;
        }
    } else if ((5U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        if (vlSelf->tb_ram_dma_fill__DOT__dma_ready) {
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 6U;
        }
    } else if ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state 
            = ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])
                ? ((0U == ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state)))
                    ? 0U : 6U) : ((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                   [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])
                                   ? 0U : (((0U == 
                                             vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                                             [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]) 
                                            & (0U == 
                                               ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state))))
                                            ? 0U : 
                                           ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal)
                                             ? 0U : 
                                            ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__reoutput_high_address)
                                              ? 2U : 3U)))));
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n)) 
                    | ((IData)(__VdfgTmp_h82709370__0) 
                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
    vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n = (1U 
                                                  & ((~ (IData)(__VdfgTmp_h82709370__0)) 
                                                     & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__fgn_rd))));
    vlSelf->tb_ram_dma_fill__DOT__bus_addr = (((~ (IData)(
                                                          (0xfU 
                                                           == (IData)(vlSelf->tb_ram_dma_fill__DOT__dack_n)))) 
                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n) 
                                                  & (IData)(vlSelf->tb_ram_dma_fill__DOT__dma_wait)))
                                               ? (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out)
                                               : vlSelf->tb_ram_dma_fill__DOT__bench_addr);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_address 
        = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
             & (6U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
            << 3U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                        & (4U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
                       << 2U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                                   & (2U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
                                  << 1U) | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                                            & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_word_count 
        = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
             & (7U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
            << 3U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                        & (5U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
                       << 2U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                                   & (3U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))) 
                                  << 1U) | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                                            & (1U == (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_adr))))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count 
        = (0x10000U | vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
           [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__dma_select]);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count 
        = (0x1ffffU & (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count 
                       - (IData)(1U)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
        [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__dma_select];
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address 
        = (0xffffU & (((1U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__chanel_0_address_hold_enable))
                       ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)
                       : (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select
                          [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]
                           ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address) 
                              - (IData)(1U)) : ((IData)(1U) 
                                                + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row 
        = ((0x77U >= (0x7fU & ((IData)(0xbU) + ((IData)(0x18U) 
                                                * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))
            ? (0x1fffU & (((0U == (0x1fU & ((IData)(0xbU) 
                                            + ((IData)(0x18U) 
                                               * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))
                            ? 0U : (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                                    (((IData)(0xcU) 
                                      + (0x7fU & ((IData)(0xbU) 
                                                  + 
                                                  ((IData)(0x18U) 
                                                   * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))) 
                                     >> 5U)] << ((IData)(0x20U) 
                                                 - 
                                                 (0x1fU 
                                                  & ((IData)(0xbU) 
                                                     + 
                                                     ((IData)(0x18U) 
                                                      * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))))) 
                          | (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                             (3U & (((IData)(0xbU) 
                                     + ((IData)(0x18U) 
                                        * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))) 
                                    >> 5U))] >> (0x1fU 
                                                 & ((IData)(0xbU) 
                                                    + 
                                                    ((IData)(0x18U) 
                                                     * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))))
            : 0U);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank 
        = ((0x77U >= (0x7fU & ((IData)(9U) + ((IData)(0x18U) 
                                              * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))
            ? (3U & (((0U == (0x1fU & ((IData)(9U) 
                                       + ((IData)(0x18U) 
                                          * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))
                       ? 0U : (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                               (((IData)(1U) + (0x7fU 
                                                & ((IData)(9U) 
                                                   + 
                                                   ((IData)(0x18U) 
                                                    * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))) 
                                >> 5U)] << ((IData)(0x20U) 
                                            - (0x1fU 
                                               & ((IData)(9U) 
                                                  + 
                                                  ((IData)(0x18U) 
                                                   * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))))) 
                     | (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                        (3U & (((IData)(9U) + ((IData)(0x18U) 
                                               * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))) 
                               >> 5U))] >> (0x1fU & 
                                            ((IData)(9U) 
                                             + ((IData)(0x18U) 
                                                * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))))
            : 0U);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (8U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (0xbU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (9U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (0xaU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (0xfU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address 
        = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
             & (6U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
            << 3U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                        & (4U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
                       << 2U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                                   & (2U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
                                  << 1U) | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                                            & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count 
        = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
             & (7U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
            << 3U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                        & (5U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
                       << 2U) | ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                                   & (3U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
                                  << 1U) | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                                            & (1U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (0xdU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
           & (0xeU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word 
        = ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state) 
           & (3U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
              [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]));
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0 
        = vlSelf->tb_ram_dma_fill__DOT__ems98_unused
        [(3U & (vlSelf->tb_ram_dma_fill__DOT__bus_addr 
                >> 0xeU))];
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h1ea43d0e__0 
        = (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open) 
                 >> (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank)));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h44e2fdf7__0 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row
        [vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank];
    tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win = (IData)(
                                                          ((0xc0000U 
                                                            == 
                                                            (0xf0000U 
                                                             & vlSelf->tb_ram_dma_fill__DOT__bus_addr)) 
                                                           & ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0) 
                                                              >> 0xaU)));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_miss 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h1ea43d0e__0) 
           & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h44e2fdf7__0) 
              != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row)));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address 
        = (0xffffffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__p1_flag)
                         ? ((IData)(0x600000U) + (0x1ffffU 
                                                  & vlSelf->tb_ram_dma_fill__DOT__bus_addr))
                         : ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win)
                             ? ((0xffc000U & ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0) 
                                              << 0xeU)) 
                                | (0x3fffU & vlSelf->tb_ram_dma_fill__DOT__bus_addr))
                             : vlSelf->tb_ram_dma_fill__DOT__bus_addr)));
    tb_ram_dma_fill__DOT__ram_address_select_n = (1U 
                                                  & (~ 
                                                     (((IData)(vlSelf->tb_ram_dma_fill__DOT__p1_flag) 
                                                       | ([&]() {
                            vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__a 
                                = vlSelf->tb_ram_dma_fill__DOT__bus_addr;
                            vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__Vfuncout 
                                = (((0xcU > (0xfU & 
                                             (vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__a 
                                              >> 0x10U))) 
                                    | (0x1dU <= (0x1fU 
                                                 & (vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__a 
                                                    >> 0xfU)))) 
                                   & (0x14U != (0x1fU 
                                                & (vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__a 
                                                   >> 0xfU))));
                        }(), (IData)(vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__Vfuncout))) 
                                                      | (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win))));
    tb_ram_dma_fill__DOT__u_ram__DOT__parked2_match 
        = ((vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address 
            == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_address) 
           & (((0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr)) 
               == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data)) 
              & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word)) 
                    | (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data_hi))))));
    tb_ram_dma_fill__DOT__u_ram__DOT__parked_match 
        = ((vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address 
            == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address) 
           & (((0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr)) 
               == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data)) 
              & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word)) 
                    | (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi))))));
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h1f356822__0 
        = (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address 
           == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command 
        = (1U & ((~ (IData)(tb_ram_dma_fill__DOT__ram_address_select_n)) 
                 & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command 
        = ((~ (IData)(tb_ram_dma_fill__DOT__ram_address_select_n)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0));
    tb_ram_dma_fill__DOT__u_ram__DOT__read_strobe_match 
        = ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h1f356822__0) 
           & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word)));
    tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match 
        = ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h1f356822__0) 
           & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data) 
               == (0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr))) 
              & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word)) 
                    | (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi))))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_fell 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command_d));
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h3d9a9fa7__0 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) 
           & (0U != vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h6a00c20b__0 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2) 
           & ((~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match)) 
              & ((~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__parked_match)) 
                 & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2) 
                       & (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__parked2_match))))));
    vlSelf->tb_ram_dma_fill__DOT__memory_access_ready 
        = (1U & ((~ ((~ (IData)(tb_ram_dma_fill__DOT__ram_address_select_n)) 
                     & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n)) 
                        | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0)))) 
                 | ((5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state) 
                    & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) 
                        & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr) 
                           & ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match) 
                              & ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count)) 
                                 & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count)))))) 
                       | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command) 
                          & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd) 
                             & ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT__read_strobe_match) 
                                & ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count)) 
                                   & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count))))))))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe 
        = ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h3d9a9fa7__0) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)) 
              & (~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_hf0bd275d__0 
        = ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h3d9a9fa7__0) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend));
    if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command) 
               & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)));
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) 
               & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)));
    } else if ((1U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 1U;
    } else if ((2U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 0U;
    } else if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 0U;
    } else if ((4U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 0U;
    } else if ((5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 0U;
    } else if ((6U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = 0U;
    }
    tb_ram_dma_fill__DOT__u_ram__DOT__idle = ((~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy) 
                                                  | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request) 
                                                     | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request)))) 
                                              & ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done) 
                                                   & (4U 
                                                      == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) 
                                                  & (0U 
                                                     == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) 
                                                 & (0x140U 
                                                    > (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe2 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_hf0bd275d__0) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2)) 
              & ((~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match)) 
                 & (~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__parked_match)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state;
    if ((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) 
             | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 1U;
        } else if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 3U;
        }
    } else if ((1U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 2U;
        }
    } else if ((2U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag)))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 5U;
        }
    } else if ((3U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command)))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 6U;
        }
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 4U;
        }
    } else if ((4U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command)))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 6U;
        }
        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag)))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 5U;
        }
    } else if ((5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if ((1U & ((((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command)) 
                     | (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr))) 
                    | (~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_match))) 
                   & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command)) 
                       | (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd))) 
                      | (~ (IData)(tb_ram_dma_fill__DOT__u_ram__DOT__read_strobe_match)))))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 0U;
        }
    } else if ((6U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)) {
        if (tb_ram_dma_fill__DOT__u_ram__DOT__idle) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 0U;
        }
    }
}

void Vtb_ram_dma_fill___024root___act_sequent__TOP__0(Vtb_ram_dma_fill___024root* vlSelf);

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_stl(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_stl\n"); );
    // Body
    if ((1ULL & vlSelf->__VstlTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___stl_sequent__TOP__0(vlSelf);
    }
    if ((3ULL & vlSelf->__VstlTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___act_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_triggers__stl(Vtb_ram_dma_fill___024root* vlSelf);

VL_ATTR_COLD bool Vtb_ram_dma_fill___024root___eval_phase__stl(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_phase__stl\n"); );
    // Init
    CData/*0:0*/ __VstlExecute;
    // Body
    Vtb_ram_dma_fill___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = vlSelf->__VstlTriggered.any();
    if (__VstlExecute) {
        Vtb_ram_dma_fill___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__act(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VactTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @([hybrid] tb_ram_dma_fill.u_ce.cpu_edge_num)\n");
    }
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 1 is active: @(posedge tb_ram_dma_fill.clk)\n");
    }
    if ((4ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 2 is active: @(posedge tb_ram_dma_fill.clk or posedge tb_ram_dma_fill.reset)\n");
    }
    if ((8ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 3 is active: @(negedge tb_ram_dma_fill.clk)\n");
    }
    if ((0x10ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 4 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__nba(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___dump_triggers__nba\n"); );
    // Body
    if ((1U & (~ (IData)(vlSelf->__VnbaTriggered.any())))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @([hybrid] tb_ram_dma_fill.u_ce.cpu_edge_num)\n");
    }
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 1 is active: @(posedge tb_ram_dma_fill.clk)\n");
    }
    if ((4ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 2 is active: @(posedge tb_ram_dma_fill.clk or posedge tb_ram_dma_fill.reset)\n");
    }
    if ((8ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 3 is active: @(negedge tb_ram_dma_fill.clk)\n");
    }
    if ((0x10ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 4 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___ctor_var_reset(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___ctor_var_reset\n"); );
    // Body
    vlSelf->tb_ram_dma_fill__DOT__clk = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__reset = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__clk_cpu = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__bench_addr = VL_RAND_RESET_I(20);
    vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__dack_n = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__hrq = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__clipw = 0;
    vlSelf->tb_ram_dma_fill__DOT__clip_cnt = 0;
    vlSelf->tb_ram_dma_fill__DOT__clip_active = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__hlda = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__aen_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__dma_wait = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__want_drq = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__p1_flag = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__p1_at = 0;
    vlSelf->tb_ram_dma_fill__DOT__p1_len = 0;
    vlSelf->tb_ram_dma_fill__DOT__p1_tick = 0;
    vlSelf->tb_ram_dma_fill__DOT__dreq = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__bus_addr = VL_RAND_RESET_I(20);
    vlSelf->tb_ram_dma_fill__DOT__dma_ready = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__memory_access_ready = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__gv_req = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__gv_timer = 0;
    vlSelf->tb_ram_dma_fill__DOT__ri_req = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__ri_addr = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__fgn_rd = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__fgn_timer = 0;
    vlSelf->tb_ram_dma_fill__DOT__s_a = VL_RAND_RESET_I(13);
    vlSelf->tb_ram_dma_fill__DOT__s_ba = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__s_cke = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__s_dq_io = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__s_ldqm = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__s_udqm = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__s_dq_out = VL_RAND_RESET_I(16);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__ems98_unused[__Vi0] = VL_RAND_RESET_I(11);
    }
    vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT____Vcellinp__sdr__dqm = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__memw_pulses = 0;
    vlSelf->tb_ram_dma_fill__DOT__wc_seen = 0;
    vlSelf->tb_ram_dma_fill__DOT__wr_accept = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr_writes = 0;
    vlSelf->tb_ram_dma_fill__DOT__tail_trace = 0;
    vlSelf->tb_ram_dma_fill__DOT__acc_prev = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_d = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__errors = 0;
    vlSelf->tb_ram_dma_fill__DOT__unnamedblk1__DOT__got = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__dq_in__en0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_acc = VL_RAND_RESET_I(9);
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num = VL_RAND_RESET_I(9);
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den = VL_RAND_RESET_I(9);
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum = VL_RAND_RESET_I(10);
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__speed_change = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_address = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_word_count = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_request_state = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__prev_write_enable_n = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select[__Vi0] = VL_RAND_RESET_I(2);
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__controller_disable = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_address = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_word_count = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[__Vi0] = VL_RAND_RESET_I(16);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[__Vi0] = VL_RAND_RESET_I(16);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[__Vi0] = VL_RAND_RESET_I(16);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[__Vi0] = VL_RAND_RESET_I(16);
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count = VL_RAND_RESET_I(17);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__dma_select = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4 = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select[__Vi0] = VL_RAND_RESET_I(2);
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__chanel_0_address_hold_enable = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dack_sense_active_high = VL_RAND_RESET_I(1);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[__Vi0] = VL_RAND_RESET_I(2);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[__Vi0] = VL_RAND_RESET_I(1);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[__Vi0] = VL_RAND_RESET_I(1);
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[__Vi0] = VL_RAND_RESET_I(2);
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__reoutput_high_address = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_bus_state = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait_Qn = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data_hi = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_address = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data_hi = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address = VL_RAND_RESET_I(25);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num = VL_RAND_RESET_I(10);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_out = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe2 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__data_bus_out_reg = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command_d = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked = VL_RAND_RESET_I(8);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_addr = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_wr = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_st = VL_RAND_RESET_I(3);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_fell = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_hf0bd275d__0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h6a00c20b__0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__addr_r = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_r = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_hi_r = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rvalid = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rdata = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req = VL_RAND_RESET_I(5);
    VL_RAND_RESET_W(120, vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt = VL_RAND_RESET_I(4);
    VL_RAND_RESET_W(80, vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack = VL_RAND_RESET_I(5);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done = VL_RAND_RESET_I(5);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant = VL_RAND_RESET_I(3);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = VL_RAND_RESET_I(3);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr = VL_RAND_RESET_I(3);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner = VL_RAND_RESET_I(3);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr = VL_RAND_RESET_I(24);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col = VL_RAND_RESET_I(9);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left = VL_RAND_RESET_I(5);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_due = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe = VL_RAND_RESET_I(4);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row = VL_RAND_RESET_I(13);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank = VL_RAND_RESET_I(2);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open = VL_RAND_RESET_I(4);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row[__Vi0] = VL_RAND_RESET_I(13);
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_miss = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h53139d90__0 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__0 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__1 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h1ea43d0e__0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h44e2fdf7__0 = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.atDefault() = VL_RAND_RESET_I(16);
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[__Vi0] = 0;
    }
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd = 0;
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 4; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[__Vi0] = 0;
    }
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_at = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_count = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__reads_served = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__writes_served = 0;
    for (int __Vi0 = 0; __Vi0 < 6; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[__Vi0] = VL_RAND_RESET_I(16);
    }
    for (int __Vi0 = 0; __Vi0 < 6; ++__Vi0) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[__Vi0] = VL_RAND_RESET_I(1);
    }
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold1 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold2 = VL_RAND_RESET_I(1);
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__addr = 0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur = VL_RAND_RESET_I(16);
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT____VdfgTmp_h854dc19a__0 = 0;
    vlSelf->__Vfunc_rotate_right__12__Vfuncout = VL_RAND_RESET_I(4);
    vlSelf->__Vfunc_rotate_right__12__source = VL_RAND_RESET_I(4);
    vlSelf->__Vfunc_rotate_right__12__rotate = VL_RAND_RESET_I(2);
    vlSelf->__Vfunc_rotate_left__14__Vfuncout = VL_RAND_RESET_I(4);
    vlSelf->__Vfunc_rotate_left__14__source = VL_RAND_RESET_I(4);
    vlSelf->__Vfunc_rotate_left__14__rotate = VL_RAND_RESET_I(2);
    vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__Vfuncout = VL_RAND_RESET_I(1);
    vlSelf->__Vfunc_tb_ram_dma_fill__DOT__u_ram__DOT__pc98_sdram_hits__17__a = VL_RAND_RESET_I(20);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = VL_RAND_RESET_I(4);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt = VL_RAND_RESET_I(4);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant = VL_RAND_RESET_I(3);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = VL_RAND_RESET_I(16);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left = VL_RAND_RESET_I(16);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt = VL_RAND_RESET_I(16);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe = VL_RAND_RESET_I(4);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left = VL_RAND_RESET_I(5);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we = VL_RAND_RESET_I(1);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr = VL_RAND_RESET_I(24);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col = VL_RAND_RESET_I(9);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard = VL_RAND_RESET_I(16);
    vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 = 0;
    vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 = 0;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r = VL_RAND_RESET_I(1);
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r = VL_RAND_RESET_I(4);
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__0 = VL_RAND_RESET_I(9);
    vlSelf->__VstlDidInit = 0;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__1 = VL_RAND_RESET_I(9);
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0 = VL_RAND_RESET_I(1);
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__reset__0 = VL_RAND_RESET_I(1);
    vlSelf->__VactDidInit = 0;
}
