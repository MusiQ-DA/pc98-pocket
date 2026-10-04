// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_ram_dma_fill.h for the primary calling header

#include "Vtb_ram_dma_fill__pch.h"
#include "Vtb_ram_dma_fill___024root.h"

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_initial__TOP(Vtb_ram_dma_fill___024root* vlSelf);
VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__0(Vtb_ram_dma_fill___024root* vlSelf);
VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__1(Vtb_ram_dma_fill___024root* vlSelf);
VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__2(Vtb_ram_dma_fill___024root* vlSelf);

void Vtb_ram_dma_fill___024root___eval_initial(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_initial\n"); );
    // Body
    Vtb_ram_dma_fill___024root___eval_initial__TOP(vlSelf);
    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__1(vlSelf);
    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__2(vlSelf);
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__0 
        = vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__1 
        = vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0 
        = vlSelf->tb_ram_dma_fill__DOT__clk;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__reset__0 
        = vlSelf->tb_ram_dma_fill__DOT__reset;
}

VL_INLINE_OPT VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__0(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__0\n"); );
    // Init
    IData/*31:0*/ tb_ram_dma_fill__DOT____Vrepeat4;
    tb_ram_dma_fill__DOT____Vrepeat4 = 0;
    IData/*31:0*/ tb_ram_dma_fill__DOT____Vrepeat6;
    tb_ram_dma_fill__DOT____Vrepeat6 = 0;
    IData/*31:0*/ tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard;
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard = 0;
    IData/*31:0*/ tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss;
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss = 0;
    IData/*31:0*/ tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i;
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__v = 0;
    CData/*3:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__rega;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__rega = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__v;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__v = 0;
    CData/*0:0*/ __Vtask_tb_ram_dma_fill__DOT__check__7__cond;
    __Vtask_tb_ram_dma_fill__DOT__check__7__cond = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__check__7__name;
    CData/*0:0*/ __Vtask_tb_ram_dma_fill__DOT__check__8__cond;
    __Vtask_tb_ram_dma_fill__DOT__check__8__cond = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__check__8__name;
    IData/*31:0*/ __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__addr;
    __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__addr = 0;
    CData/*7:0*/ __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__q;
    __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__q = 0;
    IData/*31:0*/ __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard;
    __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard = 0;
    SData/*15:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__Vfuncout;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__Vfuncout = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__addr;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__addr = 0;
    CData/*0:0*/ __Vtask_tb_ram_dma_fill__DOT__check__11__cond;
    __Vtask_tb_ram_dma_fill__DOT__check__11__cond = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__check__11__name;
    // Body
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard = 0U;
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss = 0U;
    (void)VL_VALUEPLUSARGS_INI(32, std::string{"CLIPW=%d"}, 
                               vlSelf->tb_ram_dma_fill__DOT__clipw);
    (void)VL_VALUEPLUSARGS_INI(32, std::string{"P1AT=%d"}, 
                               vlSelf->tb_ram_dma_fill__DOT__p1_at);
    (void)VL_VALUEPLUSARGS_INI(32, std::string{"P1LEN=%d"}, 
                               vlSelf->tb_ram_dma_fill__DOT__p1_len);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       475);
    vlSelf->tb_ram_dma_fill__DOT__reset = 0U;
    tb_ram_dma_fill__DOT____Vrepeat4 = 0x64U;
    while (VL_LTS_III(32, 0U, tb_ram_dma_fill__DOT____Vrepeat4)) {
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           477);
        tb_ram_dma_fill__DOT____Vrepeat4 = (tb_ram_dma_fill__DOT____Vrepeat4 
                                            - (IData)(1U));
    }
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__v = 0U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__rega = 0xcU;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__0__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__v = 0x46U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__rega = 0xbU;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__1__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__v = 0U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__rega = 4U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__2__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__v = 4U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__rega = 4U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__3__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__v = 0xffU;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__rega = 5U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__4__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__v = 0xfU;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__rega = 5U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__5__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__v = 2U;
    __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__rega = 0xaU;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       434);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 0U;
    vlSelf->tb_ram_dma_fill__DOT__bench_adr = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__rega;
    vlSelf->tb_ram_dma_fill__DOT__bench_dw = __Vtask_tb_ram_dma_fill__DOT__dmac_wr__6__v;
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 0U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       439);
    vlSelf->tb_ram_dma_fill__DOT__bench_iow_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       441);
    vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n = 1U;
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                       nullptr, 
                                                       "@(posedge tb_ram_dma_fill.clk)", 
                                                       "/work/sim/tb_ram_dma_fill.sv", 
                                                       488);
    if (VL_UNLIKELY((0xbU != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)))) {
        VL_WRITEF("  mask_register=%b after unmask (want 1011)\n",
                  4,vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register);
    }
    __Vtask_tb_ram_dma_fill__DOT__check__7__name = 
        std::string{"mode set ch2 = single"};
    __Vtask_tb_ram_dma_fill__DOT__check__7__cond = 
        (1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
         [2U]);
    if (VL_UNLIKELY((1U & (~ (IData)(__Vtask_tb_ram_dma_fill__DOT__check__7__cond))))) {
        vlSelf->tb_ram_dma_fill__DOT__errors = ((IData)(1U) 
                                                + vlSelf->tb_ram_dma_fill__DOT__errors);
        VL_WRITEF("FAIL: %@\n",-1,&(__Vtask_tb_ram_dma_fill__DOT__check__7__name));
    }
    while ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done)))) {
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           499);
    }
    vlSelf->tb_ram_dma_fill__DOT__want_drq = 1U;
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard = 0U;
    while ((VL_GTS_III(32, 0x1000U, vlSelf->tb_ram_dma_fill__DOT__memw_pulses) 
            & VL_GTS_III(32, 0x2625a00U, tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard))) {
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           503);
        tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard 
            = ((IData)(1U) + tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard);
    }
    VL_WRITEF("  fill done: pulses=%0d guard=%0d wc_seen=%0d wr_accept=%0d sdr_writes=%0d\n",
              32,vlSelf->tb_ram_dma_fill__DOT__memw_pulses,
              32,tb_ram_dma_fill__DOT__unnamedblk1__DOT__guard,
              32,vlSelf->tb_ram_dma_fill__DOT__wc_seen,
              32,vlSelf->tb_ram_dma_fill__DOT__wr_accept,
              32,vlSelf->tb_ram_dma_fill__DOT__sdr_writes);
    __Vtask_tb_ram_dma_fill__DOT__check__8__name = 
        std::string{"all strobe pulses issued"};
    __Vtask_tb_ram_dma_fill__DOT__check__8__cond = 
        (0x1000U == vlSelf->tb_ram_dma_fill__DOT__memw_pulses);
    if (VL_UNLIKELY((1U & (~ (IData)(__Vtask_tb_ram_dma_fill__DOT__check__8__cond))))) {
        vlSelf->tb_ram_dma_fill__DOT__errors = ((IData)(1U) 
                                                + vlSelf->tb_ram_dma_fill__DOT__errors);
        VL_WRITEF("FAIL: %@\n",-1,&(__Vtask_tb_ram_dma_fill__DOT__check__8__name));
    }
    vlSelf->tb_ram_dma_fill__DOT__want_drq = 0U;
    tb_ram_dma_fill__DOT____Vrepeat6 = 0x1388U;
    while (VL_LTS_III(32, 0U, tb_ram_dma_fill__DOT____Vrepeat6)) {
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           511);
        tb_ram_dma_fill__DOT____Vrepeat6 = (tb_ram_dma_fill__DOT____Vrepeat6 
                                            - (IData)(1U));
    }
    tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i = 0U;
    while (VL_GTS_III(32, 0x1000U, tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i)) {
        __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__addr 
            = ((IData)(0x400U) + tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i);
        vlSelf->tb_ram_dma_fill__DOT__bench_addr = 
            (0xfffffU & __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__addr);
        vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n = 0U;
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           454);
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           454);
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           454);
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           454);
        __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard = 0U;
        while (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__memory_access_ready)) 
                & VL_GTS_III(32, 0xfa0U, __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard))) {
            co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                               nullptr, 
                                                               "@(posedge tb_ram_dma_fill.clk)", 
                                                               "/work/sim/tb_ram_dma_fill.sv", 
                                                               457);
            __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard 
                = ((IData)(1U) + __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard);
        }
        if (VL_UNLIKELY(VL_LTES_III(32, 0xfa0U, __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__guard))) {
            VL_WRITEF("  READ TIMEOUT @%05x\n",32,__Vtask_tb_ram_dma_fill__DOT__cpu_read__9__addr);
        }
        __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__q 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command)
                ? (0xffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag)
                             ? (0xffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_out))
                             : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__data_bus_out_reg)))
                : 0U);
        vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n = 1U;
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           462);
        co_await vlSelf->__VtrigSched_hff9fd67f__0.trigger(0U, 
                                                           nullptr, 
                                                           "@(posedge tb_ram_dma_fill.clk)", 
                                                           "/work/sim/tb_ram_dma_fill.sv", 
                                                           462);
        vlSelf->tb_ram_dma_fill__DOT__unnamedblk1__DOT__got 
            = __Vtask_tb_ram_dma_fill__DOT__cpu_read__9__q;
        if (((IData)(vlSelf->tb_ram_dma_fill__DOT__unnamedblk1__DOT__got) 
             != (0xffU & (0xa5U ^ tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i)))) {
            if (VL_UNLIKELY(VL_GTS_III(32, 0x28U, tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss))) {
                VL_WRITEF("  MISS addr=%05x got=%02x want=%02x peek=%04x\n",
                          32,((IData)(0x400U) + tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i),
                          8,(IData)(vlSelf->tb_ram_dma_fill__DOT__unnamedblk1__DOT__got),
                          8,(0xffU & (0xa5U ^ tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i)),
                          16,([&]() {
                                __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__addr 
                                    = ((IData)(0x400U) 
                                       + tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i);
                                __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__Vfuncout 
                                    = ((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.exists(__Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__addr))
                                        ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store
                                       .at(__Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__addr)
                                        : 0U);
                            }(), (IData)(__Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__peek__10__Vfuncout)));
            }
            tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss 
                = ((IData)(1U) + tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss);
        }
        tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i 
            = ((IData)(1U) + tb_ram_dma_fill__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i);
    }
    VL_WRITEF("  landed mismatches: %0d / 4096\n  ram_dbg2=%08x (st=%0# wr=%0b addr=%05x lost=%0#)  ram_dbg3.blocked=%0# parks=%0#\n",
              32,tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss,
              32,(((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_st) 
                   << 0x1dU) | (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_wr) 
                                 << 0x1cU) | ((0xfffff00U 
                                               & (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_addr 
                                                  << 8U)) 
                                              | (0xffU 
                                                 & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops))))),
              3,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_st),
              1,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_wr,
              20,(0xfffffU & vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_addr),
              8,(0xffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops)),
              8,(0xffU & ((0xffffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked)) 
                          | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks) 
                             >> 0x10U))),16,(0xffffU 
                                             & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks)));
    __Vtask_tb_ram_dma_fill__DOT__check__11__name = 
        std::string{"every filled byte landed in SDRAM"};
    __Vtask_tb_ram_dma_fill__DOT__check__11__cond = 
        (0U == tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss);
    if (VL_UNLIKELY((1U & (~ (IData)(__Vtask_tb_ram_dma_fill__DOT__check__11__cond))))) {
        vlSelf->tb_ram_dma_fill__DOT__errors = ((IData)(1U) 
                                                + vlSelf->tb_ram_dma_fill__DOT__errors);
        VL_WRITEF("FAIL: %@\n",-1,&(__Vtask_tb_ram_dma_fill__DOT__check__11__name));
    }
    if ((0U == vlSelf->tb_ram_dma_fill__DOT__errors)) {
        VL_WRITEF("=== PASS tb_ram_dma_fill ===\n");
    } else {
        VL_WRITEF("=== FAIL tb_ram_dma_fill (%0d errors, %0d lost bytes) ===\n",
                  32,vlSelf->tb_ram_dma_fill__DOT__errors,
                  32,tb_ram_dma_fill__DOT__unnamedblk1__DOT__miss);
    }
    VL_FINISH_MT("/work/sim/tb_ram_dma_fill.sv", 534, "");
}

VL_INLINE_OPT VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__1(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__1\n"); );
    // Body
    co_await vlSelf->__VdlySched.delay(0x5d21dba000ULL, 
                                       nullptr, "/work/sim/tb_ram_dma_fill.sv", 
                                       539);
    VL_WRITEF("FAIL tb_ram_dma_fill (timeout: pulses=%0d drops=%0#)\n",
              32,vlSelf->tb_ram_dma_fill__DOT__memw_pulses,
              8,(0xffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops)));
    VL_FINISH_MT("/work/sim/tb_ram_dma_fill.sv", 542, "");
}

VL_INLINE_OPT VlCoroutine Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__2(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_initial__TOP__Vtiming__2\n"); );
    // Body
    while (1U) {
        co_await vlSelf->__VdlySched.delay(0x2d79ULL, 
                                           nullptr, 
                                           "/work/sim/tb_ram_dma_fill.sv", 
                                           36);
        vlSelf->tb_ram_dma_fill__DOT__clk = (1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__clk)));
    }
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___act_sequent__TOP__0(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___act_sequent__TOP__0\n"); );
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum 
        = (0x3ffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_acc) 
                     + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num)));
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num 
        = ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
            ? ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
                ? 1U : 0xb8U) : ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
                                  ? 0x5cU : 0x2eU));
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___act_sequent__TOP__1(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___act_sequent__TOP__1\n"); );
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
    CData/*0:0*/ __VdfgTmp_h82709370__0;
    __VdfgTmp_h82709370__0 = 0;
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n) 
                       | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control)))));
    vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n = ((IData)(vlSelf->tb_ram_dma_fill__DOT__bench_iow_n) 
                                                   & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n));
    __VdfgTmp_h82709370__0 = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n)) 
                                    | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n)) 
                                       & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
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
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__prev_write_enable_n)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n));
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n)) 
                    | ((IData)(__VdfgTmp_h82709370__0) 
                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
    vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n = (1U 
                                                  & ((~ (IData)(__VdfgTmp_h82709370__0)) 
                                                     & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__fgn_rd))));
    tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0 
        = vlSelf->tb_ram_dma_fill__DOT__ems98_unused
        [(3U & (vlSelf->tb_ram_dma_fill__DOT__bus_addr 
                >> 0xeU))];
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
    tb_ram_dma_fill__DOT__u_ram__DOT__ems98_win = (IData)(
                                                          ((0xc0000U 
                                                            == 
                                                            (0xf0000U 
                                                             & vlSelf->tb_ram_dma_fill__DOT__bus_addr)) 
                                                           & ((IData)(tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h262f0e28__0) 
                                                              >> 0xaU)));
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

void Vtb_ram_dma_fill___024root___eval_act(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_act\n"); );
    // Body
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___act_sequent__TOP__0(vlSelf);
    }
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___act_sequent__TOP__1(vlSelf);
    }
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_sequent__TOP__0(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_sequent__TOP__0\n"); );
    // Init
    SData/*15:0*/ tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 = 0;
    CData/*0:0*/ tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__18__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__19__what;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__Vfuncout;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__Vfuncout = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__bank;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__bank = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__row;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__row = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__col;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__col = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__21__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__22__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__23__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__24__what;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__Vfuncout;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__Vfuncout = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__bank;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__bank = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__row;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__row = 0;
    IData/*31:0*/ __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__col;
    __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__col = 0;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__26__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__27__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__28__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__29__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__30__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__31__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__32__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what;
    std::string __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__clip_cnt;
    __Vdly__tb_ram_dma_fill__DOT__clip_cnt = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__p1_tick;
    __Vdly__tb_ram_dma_fill__DOT__p1_tick = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__gv_req;
    __Vdly__tb_ram_dma_fill__DOT__gv_req = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__gv_timer;
    __Vdly__tb_ram_dma_fill__DOT__gv_timer = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__ri_req;
    __Vdly__tb_ram_dma_fill__DOT__ri_req = 0;
    IData/*23:0*/ __Vdly__tb_ram_dma_fill__DOT__ri_addr;
    __Vdly__tb_ram_dma_fill__DOT__ri_addr = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__fgn_rd;
    __Vdly__tb_ram_dma_fill__DOT__fgn_rd = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__fgn_timer;
    __Vdly__tb_ram_dma_fill__DOT__fgn_timer = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__memw_pulses;
    __Vdly__tb_ram_dma_fill__DOT__memw_pulses = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__wr_accept;
    __Vdly__tb_ram_dma_fill__DOT__wr_accept = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__sdr__DOT__cyc;
    __Vdly__tb_ram_dma_fill__DOT__sdr__DOT__cyc = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v0 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v0 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v1 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v1 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v2 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v2 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v3 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v3 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v4 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v6 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6;
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6 = 0;
    // Body
    __Vdly__tb_ram_dma_fill__DOT__p1_tick = vlSelf->tb_ram_dma_fill__DOT__p1_tick;
    __Vdly__tb_ram_dma_fill__DOT__fgn_timer = vlSelf->tb_ram_dma_fill__DOT__fgn_timer;
    __Vdly__tb_ram_dma_fill__DOT__clip_cnt = vlSelf->tb_ram_dma_fill__DOT__clip_cnt;
    __Vdly__tb_ram_dma_fill__DOT__fgn_rd = vlSelf->tb_ram_dma_fill__DOT__fgn_rd;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt;
    vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 = 0U;
    vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 = 0U;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt;
    __Vdly__tb_ram_dma_fill__DOT__gv_timer = vlSelf->tb_ram_dma_fill__DOT__gv_timer;
    __Vdly__tb_ram_dma_fill__DOT__gv_req = vlSelf->tb_ram_dma_fill__DOT__gv_req;
    __Vdly__tb_ram_dma_fill__DOT__ri_addr = vlSelf->tb_ram_dma_fill__DOT__ri_addr;
    __Vdly__tb_ram_dma_fill__DOT__ri_req = vlSelf->tb_ram_dma_fill__DOT__ri_req;
    __Vdly__tb_ram_dma_fill__DOT__sdr__DOT__cyc = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
    __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v6 = 0U;
    __Vdly__tb_ram_dma_fill__DOT__wr_accept = vlSelf->tb_ram_dma_fill__DOT__wr_accept;
    __Vdly__tb_ram_dma_fill__DOT__memw_pulses = vlSelf->tb_ram_dma_fill__DOT__memw_pulses;
    if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) {
        vlSelf->tb_ram_dma_fill__DOT__wc_seen = ((IData)(1U) 
                                                 + vlSelf->tb_ram_dma_fill__DOT__wc_seen);
    }
    if ((IData)((4U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd)))) {
        vlSelf->tb_ram_dma_fill__DOT__sdr_writes = 
            ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr_writes);
    }
    __Vdly__tb_ram_dma_fill__DOT__sdr__DOT__cyc = ((IData)(1U) 
                                                   + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc);
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
        [4U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v0 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
        [4U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v0 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
        [3U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v1 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
        [3U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v1 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
        [2U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v2 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
        [2U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v2 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
        [1U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v3 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
        [1U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v3 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
        [0U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v4 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hf936ce75__0;
    tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0 
        = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld
        [0U];
    __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v4 
        = tb_ram_dma_fill__DOT__sdr__DOT____Vlvbound_hb0be18fc__0;
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        __Vdly__tb_ram_dma_fill__DOT__fgn_rd = 0U;
        __Vdly__tb_ram_dma_fill__DOT__fgn_timer = 0U;
        __Vdly__tb_ram_dma_fill__DOT__gv_req = 0U;
        __Vdly__tb_ram_dma_fill__DOT__gv_timer = 0U;
        __Vdly__tb_ram_dma_fill__DOT__ri_req = 0U;
        __Vdly__tb_ram_dma_fill__DOT__ri_addr = 0x620000U;
    } else {
        if (vlSelf->tb_ram_dma_fill__DOT__want_drq) {
            __Vdly__tb_ram_dma_fill__DOT__fgn_timer 
                = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__fgn_timer);
            if ((0x60U == vlSelf->tb_ram_dma_fill__DOT__fgn_timer)) {
                __Vdly__tb_ram_dma_fill__DOT__fgn_timer = 0U;
                __Vdly__tb_ram_dma_fill__DOT__fgn_rd = 1U;
            } else if (((IData)(vlSelf->tb_ram_dma_fill__DOT__fgn_rd) 
                        & (0x5aU == vlSelf->tb_ram_dma_fill__DOT__fgn_timer))) {
                __Vdly__tb_ram_dma_fill__DOT__fgn_rd = 0U;
            }
        } else {
            __Vdly__tb_ram_dma_fill__DOT__fgn_rd = 0U;
            __Vdly__tb_ram_dma_fill__DOT__fgn_timer = 0U;
        }
        if (vlSelf->tb_ram_dma_fill__DOT__gv_req) {
            if ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack))) {
                __Vdly__tb_ram_dma_fill__DOT__gv_req = 0U;
            }
        } else {
            __Vdly__tb_ram_dma_fill__DOT__gv_timer 
                = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__gv_timer);
            if ((0x190U == vlSelf->tb_ram_dma_fill__DOT__gv_timer)) {
                __Vdly__tb_ram_dma_fill__DOT__gv_timer = 0U;
                __Vdly__tb_ram_dma_fill__DOT__gv_req = 1U;
            }
        }
        if (vlSelf->tb_ram_dma_fill__DOT__ri_req) {
            if ((0x10U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack))) {
                __Vdly__tb_ram_dma_fill__DOT__ri_addr 
                    = (0xffffffU & ((IData)(2U) + vlSelf->tb_ram_dma_fill__DOT__ri_addr));
                __Vdly__tb_ram_dma_fill__DOT__ri_req = 0U;
            }
        } else if (vlSelf->tb_ram_dma_fill__DOT__want_drq) {
            __Vdly__tb_ram_dma_fill__DOT__ri_req = 1U;
        }
    }
    if (vlSelf->tb_ram_dma_fill__DOT__s_cke) {
        if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd))) {
            if ((1U & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd) 
                          >> 1U)))) {
                if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd))) {
                    if ((0xffffffffU == vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                         [vlSelf->tb_ram_dma_fill__DOT__s_ba])) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__18__what 
                            = VL_SFORMATF_NX("READ on bank %0# with no row open",
                                             2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__18__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    } else if (VL_GTS_III(32, 2U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                                   - 
                                                   vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at
                                                   [vlSelf->tb_ram_dma_fill__DOT__s_ba]))) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__19__what 
                            = VL_SFORMATF_NX("tRCD violated on bank %0#",
                                             2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__19__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    } else {
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__col 
                            = (0x1ffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a));
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__row 
                            = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                            [vlSelf->tb_ram_dma_fill__DOT__s_ba];
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__reads_served 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__reads_served);
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__bank 
                            = vlSelf->tb_ram_dma_fill__DOT__s_ba;
                        __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v6 = 1U;
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__Vfuncout 
                            = ((VL_SHIFTL_III(32,32,32, __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__row, 0xbU) 
                                | VL_SHIFTL_III(32,32,32, __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__bank, 9U)) 
                               | __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__col);
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr 
                            = __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__20__Vfuncout;
                        __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6 
                            = ((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.exists(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr))
                                ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store
                               .at(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr)
                                : 0xdeadU);
                        __Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6 = 1U;
                        if (VL_UNLIKELY((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd))) {
                            VL_WRITEF("%0t  PART READ ba=%0# row=%0d col=%0# -> flat=%05x data=%04x\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,2,(IData)(vlSelf->tb_ram_dma_fill__DOT__s_ba),
                                      32,vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                                      [vlSelf->tb_ram_dma_fill__DOT__s_ba],
                                      9,(0x1ffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a)),
                                      32,vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr,
                                      16,((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.exists(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr))
                                           ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store
                                          .at(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk7__DOT__addr)
                                           : 0xdeadU));
                        }
                    }
                    if ((0x400U & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a))) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__21__what = 
                            std::string{"auto-precharge READ is not modelled"};
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__21__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    }
                } else {
                    if ((0xffffffffU == vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                         [vlSelf->tb_ram_dma_fill__DOT__s_ba])) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__22__what 
                            = VL_SFORMATF_NX("WRITE on bank %0# with no row open",
                                             2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__22__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    } else if (VL_GTS_III(32, 2U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                                   - 
                                                   vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at
                                                   [vlSelf->tb_ram_dma_fill__DOT__s_ba]))) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__23__what 
                            = VL_SFORMATF_NX("tRCD violated on bank %0#",
                                             2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__23__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    } else if (vlSelf->tb_ram_dma_fill__DOT__s_dq_io) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__24__what = 
                            std::string{"WRITE issued but the controller is not driving DQ"};
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__24__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    } else {
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__col 
                            = (0x1ffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a));
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__row 
                            = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                            [vlSelf->tb_ram_dma_fill__DOT__s_ba];
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at[vlSelf->tb_ram_dma_fill__DOT__s_ba] 
                            = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__writes_served 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__writes_served);
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__bank 
                            = vlSelf->tb_ram_dma_fill__DOT__s_ba;
                        __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__Vfuncout 
                            = ((VL_SHIFTL_III(32,32,32, __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__row, 0xbU) 
                                | VL_SHIFTL_III(32,32,32, __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__bank, 9U)) 
                               | __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__col);
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__addr 
                            = __Vfunc_tb_ram_dma_fill__DOT__sdr__DOT__flat__25__Vfuncout;
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur 
                            = ((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.exists(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__addr))
                                ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store
                               .at(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__addr)
                                : 0U);
                        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT____Vcellinp__sdr__dqm)))) {
                            vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur 
                                = ((0xff00U & (IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur)) 
                                   | (0xffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_dq_out)));
                        }
                        if ((1U & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT____Vcellinp__sdr__dqm) 
                                      >> 1U)))) {
                            vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur 
                                = ((0xffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur)) 
                                   | (0xff00U & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_dq_out)));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__store.at(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__addr) 
                            = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__unnamedblk8__DOT__cur;
                    }
                    if ((0x400U & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a))) {
                        __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__26__what = 
                            std::string{"auto-precharge WRITE is not modelled"};
                        if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                            VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                      64,VL_TIME_UNITED_Q(1000),
                                      -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__26__what));
                        }
                        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                            = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                    }
                }
            }
        } else if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd))) {
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd))) {
                if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                     [vlSelf->tb_ram_dma_fill__DOT__s_ba])) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__27__what 
                        = VL_SFORMATF_NX("ACTIVATE on bank %0# with row %0d already open",
                                         2,vlSelf->tb_ram_dma_fill__DOT__s_ba,
                                         32,vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                                         [vlSelf->tb_ram_dma_fill__DOT__s_ba]) ;
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__27__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                if (VL_GTS_III(32, 2U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                        - vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at
                                        [vlSelf->tb_ram_dma_fill__DOT__s_ba]))) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__28__what 
                        = VL_SFORMATF_NX("tRP violated on bank %0#",
                                         2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__28__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                if (VL_GTS_III(32, 6U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                        - vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at
                                        [vlSelf->tb_ram_dma_fill__DOT__s_ba]))) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__29__what 
                        = VL_SFORMATF_NX("tRC violated on bank %0#",
                                         2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__29__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                if (VL_GTS_III(32, 7U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                        - vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_at))) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__30__what = 
                        std::string{"tRFC violated: ACTIVATE too soon after AUTO REFRESH"};
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__30__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[vlSelf->tb_ram_dma_fill__DOT__s_ba] 
                    = vlSelf->tb_ram_dma_fill__DOT__s_a;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at[vlSelf->tb_ram_dma_fill__DOT__s_ba] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
                if (VL_UNLIKELY((0U != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__dbg_rd))) {
                    VL_WRITEF("%0t  PART ACT  ba=%0# row=%0d\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,2,(IData)(vlSelf->tb_ram_dma_fill__DOT__s_ba),
                              32,vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                              [vlSelf->tb_ram_dma_fill__DOT__s_ba]);
                }
            } else if ((0x400U & (IData)(vlSelf->tb_ram_dma_fill__DOT__s_a))) {
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[0U] = 0xffffffffU;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[0U] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[1U] = 0xffffffffU;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[1U] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[2U] = 0xffffffffU;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[2U] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[3U] = 0xffffffffU;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[3U] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
            } else {
                if (VL_GTS_III(32, 2U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                        - vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__wr_at
                                        [vlSelf->tb_ram_dma_fill__DOT__s_ba]))) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__31__what 
                        = VL_SFORMATF_NX("tWR violated on bank %0#",
                                         2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__31__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                if (((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                      [vlSelf->tb_ram_dma_fill__DOT__s_ba]) 
                     & VL_GTS_III(32, 4U, (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc 
                                           - vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__act_at
                                           [vlSelf->tb_ram_dma_fill__DOT__s_ba])))) {
                    __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__32__what 
                        = VL_SFORMATF_NX("tRAS violated on bank %0#",
                                         2,vlSelf->tb_ram_dma_fill__DOT__s_ba) ;
                    if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                        VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                                  64,VL_TIME_UNITED_Q(1000),
                                  -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__32__what));
                    }
                    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                        = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row[vlSelf->tb_ram_dma_fill__DOT__s_ba] = 0xffffffffU;
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__pre_at[vlSelf->tb_ram_dma_fill__DOT__s_ba] 
                    = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
            }
        } else if (VL_LIKELY((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd)))) {
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [0U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what = 
                    std::string{"AUTO REFRESH with a row open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_at 
                = vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc;
            vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_count 
                = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__ref_count);
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [1U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what = 
                    std::string{"AUTO REFRESH with a row open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [2U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what = 
                    std::string{"AUTO REFRESH with a row open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [3U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what = 
                    std::string{"AUTO REFRESH with a row open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__33__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
        } else {
            vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat 
                = (7U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__s_a) 
                         >> 4U));
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [0U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what = 
                    std::string{"MRS while a row is open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [1U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what = 
                    std::string{"MRS while a row is open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [2U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what = 
                    std::string{"MRS while a row is open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            if ((0xffffffffU != vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__open_row
                 [3U])) {
                __Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what = 
                    std::string{"MRS while a row is open"};
                if (VL_UNLIKELY(VL_GTS_III(32, 8U, vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations))) {
                    VL_WRITEF("[%0t] SDRAM VIOLATION: %@\n",
                              64,VL_TIME_UNITED_Q(1000),
                              -9,-1,&(__Vtask_tb_ram_dma_fill__DOT__sdr__DOT__complain__34__what));
                }
                vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations 
                    = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__violations);
            }
            VL_WRITEF("[%0t] SDRAM: mode register set, CAS latency %0d, A=%x\n",
                      64,VL_TIME_UNITED_Q(1000),-9,
                      32,vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat,
                      13,(IData)(vlSelf->tb_ram_dma_fill__DOT__s_a));
        }
    }
    if ((((IData)(vlSelf->tb_ram_dma_fill__DOT__want_drq) 
          & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0)) 
         & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_d))) {
        __Vdly__tb_ram_dma_fill__DOT__memw_pulses = 
            ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__memw_pulses);
        if (VL_UNLIKELY((VL_LTES_III(32, 0xff8U, vlSelf->tb_ram_dma_fill__DOT__memw_pulses) 
                         | VL_GTS_III(32, 0xaU, vlSelf->tb_ram_dma_fill__DOT__memw_pulses)))) {
            VL_WRITEF("    PLS #%0d ba=%06x t=%0t\n",
                      32,((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__memw_pulses),
                      20,vlSelf->tb_ram_dma_fill__DOT__bus_addr,
                      64,VL_TIME_UNITED_Q(1000),-9);
        }
    }
    if (((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state) 
         & (1U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state))) {
        __Vdly__tb_ram_dma_fill__DOT__wr_accept = ((IData)(1U) 
                                                   + vlSelf->tb_ram_dma_fill__DOT__wr_accept);
        if (VL_UNLIKELY(((VL_LTES_III(32, 0xff6U, vlSelf->tb_ram_dma_fill__DOT__wr_accept) 
                          | VL_GTS_III(32, 0xcU, vlSelf->tb_ram_dma_fill__DOT__wr_accept)) 
                         | (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)
                              ? vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address
                              : vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address) 
                            == vlSelf->tb_ram_dma_fill__DOT__acc_prev)))) {
            VL_WRITEF("    ACC #%0d addr=%06x (pend=%b) t=%0t\n",
                      32,((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__wr_accept),
                      24,((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)
                           ? vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address
                           : vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address),
                      1,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend),
                      64,VL_TIME_UNITED_Q(1000),-9);
        }
        vlSelf->tb_ram_dma_fill__DOT__acc_prev = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend)
                                                   ? vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address
                                                   : vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address);
    }
    if (VL_UNLIKELY((VL_GTS_III(32, 4U, vlSelf->tb_ram_dma_fill__DOT__wr_accept) 
                     & (0U != vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state)))) {
        VL_WRITEF("    t=%0t st=%0d wc=%b wrf=%b aadr=%06x adi=%04x | mpst=%0# init=%b hreq=%b gnt=%0# pack=%b pdone=%b\n",
                  64,VL_TIME_UNITED_Q(1000),-9,32,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state,
                  1,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command),
                  1,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag,
                  25,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address,
                  16,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in),
                  4,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state,
                  1,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done),
                  1,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req,
                  3,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant),
                  5,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack,
                  5,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done));
    }
    if (VL_UNLIKELY((VL_LTES_III(32, 0xffeU, vlSelf->tb_ram_dma_fill__DOT__memw_pulses) 
                     & VL_GTS_III(32, 0x258U, vlSelf->tb_ram_dma_fill__DOT__tail_trace)))) {
        vlSelf->tb_ram_dma_fill__DOT__tail_trace = 
            ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__tail_trace);
        VL_WRITEF("    T%03d mw=%b st=%0d nst=%0d wc=%b pend=%b wrf=%b wrq=%b rdy=%b mrdy=%b dst=%0d ba=%06x la=%06x pa=%06x aa=%06x adi=%04x\n",
                  32,vlSelf->tb_ram_dma_fill__DOT__tail_trace,
                  1,(1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0))),
                  32,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state,
                  32,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state,
                  1,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command),
                  1,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend,
                  1,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag),
                  1,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request,
                  1,(IData)(vlSelf->tb_ram_dma_fill__DOT__dma_ready),
                  1,vlSelf->tb_ram_dma_fill__DOT__memory_access_ready,
                  32,vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state,
                  20,vlSelf->tb_ram_dma_fill__DOT__bus_addr,
                  24,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address,
                  24,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address,
                  24,vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address,
                  16,(IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in));
    }
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__dma_wait = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_cke = 1U;
        vlSelf->tb_ram_dma_fill__DOT__aen_n = 1U;
        vlSelf->tb_ram_dma_fill__DOT__hlda = 0U;
    } else if (vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge) {
        vlSelf->tb_ram_dma_fill__DOT__dma_wait = vlSelf->tb_ram_dma_fill__DOT__aen_n;
        vlSelf->tb_ram_dma_fill__DOT__aen_n = vlSelf->tb_ram_dma_fill__DOT__hlda;
        vlSelf->tb_ram_dma_fill__DOT__hlda = vlSelf->tb_ram_dma_fill__DOT__hrq;
    }
    if (((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
         | (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n))) {
        __Vdly__tb_ram_dma_fill__DOT__clip_cnt = 0U;
        vlSelf->tb_ram_dma_fill__DOT__clip_active = 0U;
    } else if ((0U != vlSelf->tb_ram_dma_fill__DOT__clipw)) {
        if ((vlSelf->tb_ram_dma_fill__DOT__clip_cnt 
             == (vlSelf->tb_ram_dma_fill__DOT__clipw 
                 - (IData)(1U)))) {
            vlSelf->tb_ram_dma_fill__DOT__clip_active = 1U;
        } else {
            __Vdly__tb_ram_dma_fill__DOT__clip_cnt 
                = ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__clip_cnt);
        }
    }
    if (vlSelf->tb_ram_dma_fill__DOT__want_drq) {
        if (VL_LTES_III(32, 0U, vlSelf->tb_ram_dma_fill__DOT__p1_at)) {
            __Vdly__tb_ram_dma_fill__DOT__p1_tick = 
                ((IData)(1U) + vlSelf->tb_ram_dma_fill__DOT__p1_tick);
            vlSelf->tb_ram_dma_fill__DOT__p1_flag = 
                (VL_GTES_III(32, vlSelf->tb_ram_dma_fill__DOT__p1_tick, vlSelf->tb_ram_dma_fill__DOT__p1_at) 
                 & VL_LTS_III(32, vlSelf->tb_ram_dma_fill__DOT__p1_tick, 
                              (vlSelf->tb_ram_dma_fill__DOT__p1_at 
                               + vlSelf->tb_ram_dma_fill__DOT__p1_len)));
        }
    } else {
        __Vdly__tb_ram_dma_fill__DOT__p1_tick = 0U;
        vlSelf->tb_ram_dma_fill__DOT__p1_flag = 0U;
    }
    vlSelf->tb_ram_dma_fill__DOT__fgn_timer = __Vdly__tb_ram_dma_fill__DOT__fgn_timer;
    vlSelf->tb_ram_dma_fill__DOT__fgn_rd = __Vdly__tb_ram_dma_fill__DOT__fgn_rd;
    vlSelf->tb_ram_dma_fill__DOT__gv_timer = __Vdly__tb_ram_dma_fill__DOT__gv_timer;
    vlSelf->tb_ram_dma_fill__DOT__gv_req = __Vdly__tb_ram_dma_fill__DOT__gv_req;
    vlSelf->tb_ram_dma_fill__DOT__ri_addr = __Vdly__tb_ram_dma_fill__DOT__ri_addr;
    vlSelf->tb_ram_dma_fill__DOT__ri_req = __Vdly__tb_ram_dma_fill__DOT__ri_req;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cyc = __Vdly__tb_ram_dma_fill__DOT__sdr__DOT__cyc;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[5U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[4U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v1;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[3U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v2;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[2U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v3;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[1U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v4;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[0U] = 0U;
    if (__Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_vld__v6) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_vld[0U] = 1U;
    }
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[5U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v0;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[4U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v1;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[3U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v2;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[2U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v3;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[1U] 
        = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v4;
    vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[0U] = 0U;
    if (__Vdlyvset__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6) {
        vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__sdr__DOT__rd_data__v6;
    }
    vlSelf->tb_ram_dma_fill__DOT__memw_pulses = __Vdly__tb_ram_dma_fill__DOT__memw_pulses;
    vlSelf->tb_ram_dma_fill__DOT__wr_accept = __Vdly__tb_ram_dma_fill__DOT__wr_accept;
    vlSelf->tb_ram_dma_fill__DOT__clip_cnt = __Vdly__tb_ram_dma_fill__DOT__clip_cnt;
    vlSelf->tb_ram_dma_fill__DOT__p1_tick = __Vdly__tb_ram_dma_fill__DOT__p1_tick;
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
    vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_d = (1U 
                                                  & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0)));
    vlSelf->tb_ram_dma_fill__DOT__dq_in__en0 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT____VdfgTmp_h854dc19a__0)
                                                 ? 0xffffU
                                                 : 
                                                ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold1)
                                                  ? 0xffffU
                                                  : 
                                                 ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold2)
                                                   ? 0xffffU
                                                   : 0U)));
}

extern const VlUnpacked<CData/*0:0*/, 128> Vtb_ram_dma_fill__ConstPool__TABLE_hdbaa290e_0;
extern const VlUnpacked<CData/*0:0*/, 128> Vtb_ram_dma_fill__ConstPool__TABLE_ha0c4f5bc_0;

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_sequent__TOP__1(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_sequent__TOP__1\n"); );
    // Init
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
    CData/*6:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__clk_cpu;
    __Vdly__tb_ram_dma_fill__DOT__clk_cpu = 0;
    CData/*7:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v0;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v0 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v1;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v1 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v0;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v0 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v1;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v1 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v0;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v0 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v1;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v1 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v0;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v0 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v1;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v1 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v5;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v5 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v6 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v5;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v5 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v6 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v5;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v5 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v6 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v5;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v5 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v6;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v6 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v10;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v10 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v11;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v11 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v10;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v10 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v11;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v11 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v10;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v10 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v11;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v11 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v10;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v10 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v11;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v11 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v15;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v15 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v16;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v16 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v15;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v15 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v16;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v16 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v15;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v15 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v16;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v16 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v15;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v15 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v16;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v16 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 0;
    CData/*3:0*/ __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18;
    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 0;
    CData/*7:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 0;
    SData/*15:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19 = 0;
    CData/*0:0*/ __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19 = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v0 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v0 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v1 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v1 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v2 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v2 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v3 = 0;
    CData/*0:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v3 = 0;
    CData/*1:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3 = 0;
    IData/*31:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait;
    __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 = 0;
    IData/*23:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address = 0;
    CData/*7:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data = 0;
    CData/*7:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word = 0;
    CData/*1:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count = 0;
    CData/*1:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count = 0;
    CData/*3:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count = 0;
    SData/*15:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks = 0;
    SData/*15:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops = 0;
    CData/*7:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy = 0;
    CData/*0:0*/ __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = 0;
    CData/*31:0*/ __Vtemp_21;
    CData/*31:0*/ __Vtemp_22;
    // Body
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection;
    __Vdly__tb_ram_dma_fill__DOT__clk_cpu = vlSelf->tb_ram_dma_fill__DOT__clk_cpu;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing;
    __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait 
        = vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v0 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v1 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v5 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v6 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v10 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v11 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v15 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v16 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v0 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v1 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v5 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v6 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v10 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v11 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v15 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v16 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19 = 0U;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v0 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v1 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v5 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v6 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v10 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v11 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v15 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v16 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v0 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v1 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v5 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v6 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v10 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v11 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v15 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v16 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 0U;
    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19 = 0U;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r;
    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend;
    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock;
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                    & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                        ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                           >> 6U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low)))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                          ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 5U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection)))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__chanel_0_address_hold_enable 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                          ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 1U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__chanel_0_address_hold_enable)))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                          ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 3U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing)))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v0 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [0U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 5U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select
                         [0U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v1 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [1U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 5U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select
                         [1U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v2 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [2U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 5U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select
                         [2U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v3 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [3U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 5U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select
                         [3U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v0 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [0U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 4U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                         [0U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v1 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [1U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 4U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                         [1U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v2 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [2U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 4U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                         [2U]))));
    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v3 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                          & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                             [3U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                       >> 4U) : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable
                         [3U]))));
    __Vtableidx1 = (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait_Qn) 
                     << 6U) | (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait) 
                                << 5U) | (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state) 
                                           << 4U) | 
                                          (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_bus_state) 
                                            << 3U) 
                                           | (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait) 
                                               << 2U) 
                                              | (((IData)(vlSelf->tb_ram_dma_fill__DOT__memory_access_ready) 
                                                  << 1U) 
                                                 | (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)))))));
    __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait 
        = Vtb_ram_dma_fill__ConstPool__TABLE_hdbaa290e_0
        [__Vtableidx1];
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait_Qn 
        = Vtb_ram_dma_fill__ConstPool__TABLE_ha0c4f5bc_0
        [__Vtableidx1];
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                    & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                        ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                           >> 4U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority)))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__controller_disable 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                 & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                    & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                        ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                           >> 2U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__controller_disable)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
           & ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
               ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait)
               : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait)));
    vlSelf->tb_ram_dma_fill__DOT__hrq = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                                         & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                                            & ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                                                ? (
                                                   (1U 
                                                    == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state) 
                                                   | ((0U 
                                                       != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state) 
                                                      & (IData)(vlSelf->tb_ram_dma_fill__DOT__hrq)))
                                                : (IData)(vlSelf->tb_ram_dma_fill__DOT__hrq))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
              & ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge)
                  ? ((0U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                     & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process))
                  : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
              & ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                  ? ((6U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                     & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_s4)
                         ? (~ (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count 
                               >> 0x10U)) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count)))
                  : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
              & ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge)
                  ? ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state) 
                     & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count) 
                        | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process)))
                  : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal))));
    vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n = 
        ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
         | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
            | ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                ? ((~ ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                       & (1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                          [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]))) 
                   & ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                      | (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)))
                : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                 & ((~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                        | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag) 
                           & (0xcU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))))) 
                    & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag) 
                        & (0xcU == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address))) 
                       | (((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address)) 
                           | ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count)) 
                              | (((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_address)) 
                                  & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_address))) 
                                 | ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_word_count)) 
                                    & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_word_count))))))
                           ? (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer))
                           : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer))))));
    vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n = 
        ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
         | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
            | ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                ? ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                   | ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                       [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])
                       ? ((~ ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                              & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection) 
                                 | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing)))) 
                          & ((4U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                             & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n)))
                       : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n)))
                : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n))));
    vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n = ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                                                  | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                                                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                                                         ? 
                                                        ((~ 
                                                          ((3U 
                                                            == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                                           & (2U 
                                                              == 
                                                              vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                                                              [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]))) 
                                                         & ((6U 
                                                             == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                                            | (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n)))
                                                         : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n))));
    vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n = ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                                                  | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                                                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge)
                                                         ? 
                                                        ((6U 
                                                          == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                                         | ((1U 
                                                             == 
                                                             vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                                                             [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select])
                                                             ? 
                                                            ((~ 
                                                              ((3U 
                                                                == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection) 
                                                                  | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing)))) 
                                                             & ((4U 
                                                                 != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                                                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n)))
                                                             : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n)))
                                                         : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__reoutput_high_address 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
           & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
              & ((3U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                 & (((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) 
                     & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word))
                     ? ((1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out) 
                               >> 8U)) != (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address) 
                                                 >> 8U)))
                     : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__reoutput_high_address)))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = ((0xeU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register)) 
           | (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                    & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                       & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register) 
                           & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                              == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                              [0U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                        >> 2U) : ((~ 
                                                   ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                                    & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal))) 
                                                  & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register)))))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = ((0xdU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register)) 
           | (2U & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                     & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                        & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register) 
                            & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                               == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                               [1U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                         >> 2U) : (
                                                   (~ 
                                                    ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                                     & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                        >> 1U))) 
                                                   & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register) 
                                                      >> 1U))))) 
                    << 1U)));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = ((0xbU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register)) 
           | (4U & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                     & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                        & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register) 
                            & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                               == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                               [2U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                         >> 2U) : (
                                                   (~ 
                                                    ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                                     & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                        >> 2U))) 
                                                   & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register) 
                                                      >> 2U))))) 
                    << 2U)));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = ((7U & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register)) 
           | (8U & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                     & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                        & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_request_register) 
                            & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                               == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                               [3U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                         >> 2U) : (
                                                   (~ 
                                                    ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                                     & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                        >> 3U))) 
                                                   & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register) 
                                                      >> 3U))))) 
                    << 3U)));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = ((0xeU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)) 
           | (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                    | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                       | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register)) 
                          & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register) 
                              & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                                 == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                                 [0U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                           >> 2U) : 
                             ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register)
                               ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)
                               : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                    & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                                   & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable))) 
                                  | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)))))))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = ((0xdU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)) 
           | (2U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                        | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register)) 
                           & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register) 
                               & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                                  == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                                  [1U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                            >> 2U) : 
                              ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register)
                                ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                   >> 1U) : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                  >> 1U)) 
                                              & (~ 
                                                 ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable) 
                                                  >> 1U))) 
                                             | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register) 
                                                >> 1U))))))) 
                    << 1U)));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = ((0xbU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)) 
           | (4U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                        | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register)) 
                           & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register) 
                               & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                                  == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                                  [2U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                            >> 2U) : 
                              ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register)
                                ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                   >> 2U) : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                  >> 2U)) 
                                              & (~ 
                                                 ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable) 
                                                  >> 2U))) 
                                             | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register) 
                                                >> 2U))))))) 
                    << 2U)));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = ((7U & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register)) 
           | (8U & (((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) 
                        | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__clear_mask_register)) 
                           & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__set_or_reset_mask_register) 
                               & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                                  == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__bit_select
                                  [3U])) ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                            >> 2U) : 
                              ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mask_register)
                                ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                   >> 3U) : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal) 
                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                  >> 3U)) 
                                              & (~ 
                                                 ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__autoinit_enable) 
                                                  >> 3U))) 
                                             | ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register) 
                                                >> 3U))))))) 
                    << 3U)));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dack_sense_active_high 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
               && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_command_register)
                          ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 7U) : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dack_sense_active_high)))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = ((0xeU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock)) 
           | (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                    & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                       & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request) 
                          & ((((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) 
                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma)) 
                              & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                             | ((~ ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff)) 
                                    & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)))) 
                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock))))))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = ((0xdU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock)) 
           | (2U & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                     << 1U) & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                                << 1U) & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request) 
                                          & (((((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) 
                                                << 1U) 
                                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma)) 
                                              & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                                             | (((~ 
                                                  ((~ 
                                                    ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff) 
                                                     >> 1U)) 
                                                   & (~ 
                                                      ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                       >> 1U)))) 
                                                 << 1U) 
                                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock))))))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = ((0xbU & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock)) 
           | (4U & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                     << 2U) & (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)) 
                                << 2U) & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request) 
                                          & (((((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) 
                                                << 2U) 
                                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma)) 
                                              & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                                             | (((~ 
                                                  ((~ 
                                                    ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff) 
                                                     >> 2U)) 
                                                   & (~ 
                                                      ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                                       >> 2U)))) 
                                                 << 2U) 
                                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock))))))));
    __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = ((7U & (IData)(__Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock)) 
           | (0xfffffff8U & (((((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                                & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear))) 
                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__edge_request) 
                                  >> 3U)) << 3U) & 
                             (((((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) 
                                 << 3U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma)) 
                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)) 
                              | (((~ ((~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff) 
                                          >> 3U)) & 
                                      (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal) 
                                          >> 3U)))) 
                                  << 3U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock))))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data_hi = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__prev_write_enable_n 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
           | ((IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n) 
              | ((IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n) 
                 | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control))));
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v3;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v3;
        __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2 = 0U;
        __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3 = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3;
        vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait 
            = __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate = 3U;
        __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal = 0U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v0 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v5 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v10 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v15 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v0 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v5 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v10 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v15 = 1U;
        __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v0 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v5 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v10 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v15 = 1U;
    } else {
        if ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe) 
              | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe2)) 
             & (0xffffU != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks)))) {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks 
                = (0xffffU & ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks)));
        }
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_parks;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__address_decrement_select__v3;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__autoinitialization_enable__v3;
        __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus 
            = ((1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n)) 
                      & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n))))
                ? (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_dw)
                : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus));
        if (((((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command_d)) 
               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command)) 
              & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_hf0bd275d__0) 
                 & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h6a00c20b__0))) 
             & (0xffU != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked)))) {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked 
                = (0xffU & ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked)));
        }
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_blocked;
        if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) {
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2 = 0U;
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3 = 0U;
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate = 3U;
            __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal = 0U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v1 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v6 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v11 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v16 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v1 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v6 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v11 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v16 = 1U;
            __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state = 0U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v1 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v6 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v11 = 1U;
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v16 = 1U;
        } else {
            if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                 & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                    == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                    [0U]))) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0 
                    = (3U & ((3U != (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                           >> 6U)))
                              ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                 >> 2U) : 3U));
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0 
                    = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 6U));
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                       [0U]);
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                       [0U]);
            }
            if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                 & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                    == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                    [1U]))) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1 
                    = (3U & ((3U != (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                           >> 6U)))
                              ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                 >> 2U) : 3U));
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1 
                    = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 6U));
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                       [1U]);
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                       [1U]);
            }
            if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                 & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                    == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                    [2U]))) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2 
                    = (3U & ((3U != (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                           >> 6U)))
                              ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                 >> 2U) : 3U));
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2 
                    = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 6U));
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                       [2U]);
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                       [2U]);
            }
            if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_mode_register) 
                 & ((3U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus)) 
                    == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__bit_select
                    [3U]))) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3 
                    = (3U & ((3U != (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                           >> 6U)))
                              ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                                 >> 2U) : 3U));
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3 
                    = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus) 
                             >> 6U));
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type
                       [3U]);
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3 
                    = (3U & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
                       [3U]);
            }
            vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate 
                = ((1U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                    ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select)
                    : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_rotate));
            __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal 
                = ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)
                    ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma)
                    : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal));
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2 = 8U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3 = 0U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                    [0U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4 = 1U;
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4 
                    = (0xffffU & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                   & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                                   ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                                  [0U] : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                                           & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                                           ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count
                                           : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                                          [0U])));
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4 = 1U;
            }
            if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7 = 8U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8 = 0U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                    [1U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9 = 1U;
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9 
                    = (0xffffU & ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                    >> 1U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                                   ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                                  [1U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                             >> 1U) 
                                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                                           & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                                           ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count
                                           : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                                          [1U])));
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9 = 1U;
            }
            if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12 = 8U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13 = 0U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                    [2U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14 = 1U;
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14 
                    = (0xffffU & ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                    >> 2U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                                   ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                                  [2U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                             >> 2U) 
                                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                                           & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                                           ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count
                                           : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                                          [2U])));
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14 = 1U;
            }
            if ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_word_count))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17 = 8U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18 = 0U;
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                    [3U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19 = 1U;
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19 
                    = (0xffffU & ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                    >> 3U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                                   ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                                  [3U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                                             >> 3U) 
                                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                                           & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                                           ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_word_count
                                           : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                                          [3U])));
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19 = 1U;
            }
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                    [0U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4 = 1U;
            }
            if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                    [1U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9 = 1U;
            }
            if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                    [2U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14 = 1U;
            }
            if ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
                if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17 = 8U;
                } else {
                    __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 
                        = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                    __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 1U;
                    __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18 = 0U;
                }
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                    [3U];
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19 = 1U;
            }
            __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state 
                = ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge)
                    ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state
                    : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state);
        }
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode__v3;
        vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait 
            = __Vdly__tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__terminal_count;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__external_end_of_process;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__extended_write_selection;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__compressed_timing;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v0;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v1;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v2;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_type__v3;
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command) {
            if (vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) {
                if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count))) {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count 
                        = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count) 
                                 - (IData)(1U)));
                } else if (((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count)) 
                            & (5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state))) {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count 
                        = (0xfU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count) 
                                   - (IData)(1U)));
                }
            }
        } else {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count 
                = vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count = 0U;
        }
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__read_wait_count;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_rd_wait_count;
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command) {
            if (vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge) {
                if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count))) {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count 
                        = (3U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count) 
                                 - (IData)(1U)));
                } else if (((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count)) 
                            & (5U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state))) {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count 
                        = (0xfU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count) 
                                   - (IData)(1U)));
                }
            }
        } else {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count = 0U;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count = 0U;
        }
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__write_wait_count;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count 
            = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__vram_wr_wait_count;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v1) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v2))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v3))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v4;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v5) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v6) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v7))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v8))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v9;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v10) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v11) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v12))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v13))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v14;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v15) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v16) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v17))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v18))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_word_count__v19;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v1) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v2))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v3))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v4;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v5) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v6) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v7))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v8))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v9;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v10) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v11) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v12))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v13))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v14;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v15) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v16) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v17))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v18))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_word_count__v19;
    }
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v0 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v5 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v10 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v15 = 1U;
    } else if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear) {
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v1 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v6 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v11 = 1U;
        __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v16 = 1U;
    } else {
        if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
            if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2 = 8U;
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3 = 0U;
            }
        } else {
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4 
                = (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                    & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                    ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                   [0U] : ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                             & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)
                            : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                           [0U]));
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4 = 1U;
        }
        if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
            if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7 = 8U;
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8 = 0U;
            }
        } else {
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9 
                = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                     >> 1U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                    ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                   [1U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                              >> 1U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)
                            : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                           [1U]));
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9 = 1U;
        }
        if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
            if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12 = 8U;
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13 = 0U;
            }
        } else {
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14 
                = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                     >> 2U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                    ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                   [2U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                              >> 2U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)
                            : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                           [2U]));
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14 = 1U;
        }
        if ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__write_base_and_current_address))) {
            if (vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer) {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17 = 8U;
            } else {
                __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 
                    = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
                __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 1U;
                __Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18 = 0U;
            }
        } else {
            __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19 
                = ((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                     >> 3U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__initialize_current_register))
                    ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                   [3U] : (((((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__transfer_register_select) 
                              >> 3U) & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word)) 
                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge))
                            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__temporary_address)
                            : vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                           [3U]));
            __Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19 = 1U;
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__byte_pointer;
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v1) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v2))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v3))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v4;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v5) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v6) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v7))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v8))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v9;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v10) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v11) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v12))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v13))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v14;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v15) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v16) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v17))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v18))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__base_address__v19;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__request_register;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__end_of_process_internal;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__mask_register;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__internal_data_bus;
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__data_bus_out_reg = 0U;
        vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out = 0U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__data_bus_out_reg 
            = (0xffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag)
                         ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_out)
                         : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__data_bus_out_reg)));
        vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)
                ? 0U : ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge)
                         ? vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                        [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__dma_select]
                         : (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out)));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v0) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v1) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[0U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v2))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[0U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [0U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v3))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[0U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v4;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v5) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v6) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[1U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v7))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[1U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [1U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v8))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[1U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v9;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v10) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v11) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[2U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v12))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[2U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [2U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v13))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[2U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v14;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v15) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v16) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[3U] = 0U;
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v17))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[3U] 
            = (((~ ((IData)(0xffU) << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18))) 
                & vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address
                [3U]) | (0xffffU & ((IData)(__Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18) 
                                    << (IData)(__Vdlyvlsb__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v18))));
    }
    if (__Vdlyvset__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address[3U] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__current_address__v19;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock 
        = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_lock;
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal;
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_acc = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_addr = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_wr = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_st = 0U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)
                ? 0U : ((IData)(vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge)
                         ? ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state)
                             ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal)
                             : ((0U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state)
                                 ? 0U : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff)))
                         : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff)));
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__dma_acknowledge_internal;
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_acc 
            = ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
                ? 0U : (0x1ffU & (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum) 
                                   >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den))
                                   ? ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum) 
                                      - (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den))
                                   : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum))));
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_data 
            = (0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr));
        if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_strobe_fell) 
             & ((0U != vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state) 
                & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend) 
                   & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_h6a00c20b__0))))) {
            if ((0xffffU != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops))) {
                __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops 
                    = (0xffffU & ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops)));
            }
            if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops))) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_addr 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_wr 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drop_st 
                    = (7U & vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state);
            }
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__dbg_drops;
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
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_bus_state 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
           | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command_d 
        = ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset))) 
           && (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_command));
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
    vlSelf->tb_ram_dma_fill__DOT__dma_ready = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__prev_ready_n_or_wait)) 
                                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__ready_n_or_wait_Qn));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control 
        = ((0U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
           && ((1U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
               && ((2U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                   || ((3U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                       || ((4U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                           || ((5U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state) 
                               || (6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__state)))))));
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
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_word_count = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__addr_r = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_r = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_hi_r = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_out = 0U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_address 
            = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_address;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Address_And_Count_Registers__DOT__prev_read_current_word_count 
            = vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__read_current_word_count;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__stable_address 
            = vlSelf->tb_ram_dma_fill__DOT__bench_adr;
        if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy) 
             & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_r 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_hi_r 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_in_hi;
        }
        if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rvalid) 
             & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant)))) {
            if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat)))) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_data_out 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rdata;
                __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = 1U;
            } else {
                __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = 0U;
            }
        }
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy) {
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack))) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req = 0U;
            }
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done))) {
                __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy = 0U;
            }
        } else if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request) 
                    | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_request))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req = 1U;
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_request;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__addr_r 
                = (0xffffffU & vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_address);
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r 
                = ((2U <= (0x1ffU & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__access_num)))
                    ? 1U : 0U);
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat = 0U;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy = 1U;
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__rbeat;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy;
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
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        __Vdly__tb_ram_dma_fill__DOT__clk_cpu = 0U;
        vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge = 0U;
        vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge = 0U;
        vlSelf->tb_ram_dma_fill__DOT__clk_cpu = __Vdly__tb_ram_dma_fill__DOT__clk_cpu;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi = 0U;
        __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word = 0U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge = 0U;
        vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge = 0U;
        if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))) {
            if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_phase_sum) 
                 >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den))) {
                if (vlSelf->tb_ram_dma_fill__DOT__clk_cpu) {
                    vlSelf->tb_ram_dma_fill__DOT__cpu_ce_negedge = 1U;
                } else {
                    vlSelf->tb_ram_dma_fill__DOT__cpu_ce_posedge = 1U;
                }
                __Vdly__tb_ram_dma_fill__DOT__clk_cpu 
                    = (1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__clk_cpu)));
            }
        }
        vlSelf->tb_ram_dma_fill__DOT__clk_cpu = __Vdly__tb_ram_dma_fill__DOT__clk_cpu;
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dma_request_ff 
            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__master_clear)
                ? 0U : (0xfU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low)
                                 ? (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dreq))
                                 : (IData)(vlSelf->tb_ram_dma_fill__DOT__dreq))));
        vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low 
            = __Vdly__tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__dreq_sense_active_low;
        if (((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state) 
             & (1U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr = 1U;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd = 0U;
            if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word;
                if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2) {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_address;
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data;
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data_hi;
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word;
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 1U;
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 = 0U;
                } else {
                    __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 0U;
                }
            } else {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data 
                    = (0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr));
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_data_hi = 0U;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word = 0U;
                __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 0U;
            }
        } else if (((0U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state) 
                    & (3U == vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_rd 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_command;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_live_wr = 0U;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_address 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__accept_word = 0U;
        }
        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe) {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend = 1U;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address 
                = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data 
                = (0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr));
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi = 0U;
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word = 0U;
        } else if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe2) {
            __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 = 1U;
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend2;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_data_hi;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_word 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_word;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend_address 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__pend_address;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend 
        = __Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__wc_pend;
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
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select = 0U;
    } else if (vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__speed_change) {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select = 0U;
    }
    __Vtemp_21 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority)
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
        = __Vtemp_21;
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
    __Vtemp_22 = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__rotating_priority)
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
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data_hi = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_address = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data = 0U;
    } else {
        if ((1U & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe)))) {
            if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__new_write_strobe2) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data_hi = 0U;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_word = 0U;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_address 
                    = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__latch_address;
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__pend2_data 
                    = (0xffU & (0xa5U ^ vlSelf->tb_ram_dma_fill__DOT__bus_addr));
            }
        }
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__state 
            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__next_state;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = __Vtemp_22;
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Priority_Encoder__DOT__controller_disable)
            ? 0U : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__encoded_dma));
    vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait = 0U;
    if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))) {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den 
            = ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select))
                ? 1U : 0xc9U);
        vlSelf->tb_ram_dma_fill__DOT__ram_rd_wait = 1U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_den = 0xc9U;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__speed_change 
        = (0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__active_clk_select));
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
    vlSelf->tb_ram_dma_fill__DOT____Vcellinp__sdr__dqm 
        = (((IData)(vlSelf->tb_ram_dma_fill__DOT__s_udqm) 
            << 1U) | (IData)(vlSelf->tb_ram_dma_fill__DOT__s_ldqm));
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_comb__TOP__0(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_comb__TOP__0\n"); );
    // Init
    CData/*0:0*/ __VdfgTmp_h82709370__0;
    __VdfgTmp_h82709370__0 = 0;
    // Body
    vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n = ((IData)(vlSelf->tb_ram_dma_fill__DOT__bench_iow_n) 
                                                   & (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_iow_out_n));
    __VdfgTmp_h82709370__0 = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memrd_n)) 
                                    | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__bench_memrd_n)) 
                                       & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT____VdfgTmp_heded080f__0 
        = (1U & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__clip_active) 
                    | (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_memwr_n))));
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__read_flag 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_cs_n) 
                       | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__lock_bus_control)))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_req 
        = (((IData)(vlSelf->tb_ram_dma_fill__DOT__ri_req) 
            << 4U) | (((IData)(vlSelf->tb_ram_dma_fill__DOT__gv_req) 
                       << 3U) | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__req)));
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
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__write_flag 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Bus_Control_Logic__DOT__prev_write_enable_n)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n));
    vlSelf->tb_ram_dma_fill__DOT__u_ready__DOT__bus_state 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_ior_out_n)) 
                 | ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__ab_io_write_n)) 
                    | ((IData)(__VdfgTmp_h82709370__0) 
                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n)))));
    vlSelf->tb_ram_dma_fill__DOT__all_mem_rd_n = (1U 
                                                  & ((~ (IData)(__VdfgTmp_h82709370__0)) 
                                                     & (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__fgn_rd))));
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
    vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__next_word 
        = ((6U == vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__next_state) 
           & (3U != vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__transfer_mode
              [vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_select]));
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
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_sequent__TOP__2(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_sequent__TOP__2\n"); );
    // Init
    CData/*1:0*/ __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0;
    __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 = 0;
    SData/*12:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 = 0;
    CData/*1:0*/ __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1;
    __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 = 0;
    SData/*12:0*/ __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1;
    __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 = 0;
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rvalid 
        = (1U & ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__reset)) 
                 & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe) 
                    >> 2U)));
    if (vlSelf->tb_ram_dma_fill__DOT__reset) {
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 7U;
        vlSelf->tb_ram_dma_fill__DOT__s_a = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_ba = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_dq_out = 0U;
        vlSelf->tb_ram_dma_fill__DOT__s_dq_io = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left = 0x2710U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard = 0U;
        vlSelf->tb_ram_dma_fill__DOT__dreq = 0U;
    } else {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 7U;
        vlSelf->tb_ram_dma_fill__DOT__s_dq_io = 1U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack = 0U;
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done = 0U;
        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe 
            = (0xeU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe) 
                       << 1U));
        if ((0xffffU != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt))) {
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt 
                = (0xffffU & ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt)));
        }
        if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer 
                = (0xffffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer) 
                              - (IData)(1U)));
        }
        if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard))) {
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard 
                = (0xffffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard) 
                              - (IData)(1U)));
        }
        if ((8U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
            if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 0U;
            } else if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                    if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 3U;
                        vlSelf->tb_ram_dma_fill__DOT__s_a 
                            = (0x1fffU & (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
                                          >> 0xbU));
                        vlSelf->tb_ram_dma_fill__DOT__s_ba 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank;
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open 
                            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open) 
                               | (0xfU & ((IData)(1U) 
                                          << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank))));
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 5U;
                        __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 
                            = (0x1fffU & (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
                                          >> 0xbU));
                        vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 = 1U;
                        __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank;
                    }
                } else if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 4U;
                }
            } else if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 1U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 4U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 0xaU;
                }
            } else if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__1 = 1U;
                if ((4U >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))) {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done 
                        = (((~ ((IData)(1U) << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))) 
                            & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done)) 
                           | (0x1fU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__1) 
                                       << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))));
                }
                vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 4U;
            }
        } else if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
            if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 6U;
                } else {
                    vlSelf->tb_ram_dma_fill__DOT__s_ba 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank;
                    vlSelf->tb_ram_dma_fill__DOT__s_a 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col;
                    if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we) {
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt 
                            = (0xfU & ((IData)(1U) 
                                       + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt)));
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 4U;
                        vlSelf->tb_ram_dma_fill__DOT__s_dq_out 
                            = ((0x4fU >= (0x7fU & VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U)))
                                ? (0xffffU & (((0U 
                                                == 
                                                (0x1fU 
                                                 & VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U)))
                                                ? 0U
                                                : (
                                                   vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[
                                                   (((IData)(0xfU) 
                                                     + 
                                                     (0x7fU 
                                                      & VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U))) 
                                                    >> 5U)] 
                                                   << 
                                                   ((IData)(0x20U) 
                                                    - 
                                                    (0x1fU 
                                                     & VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U))))) 
                                              | (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[
                                                 (3U 
                                                  & (VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U) 
                                                     >> 5U))] 
                                                 >> 
                                                 (0x1fU 
                                                  & VL_SHIFTL_III(7,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant), 4U)))))
                                : 0U);
                        vlSelf->tb_ram_dma_fill__DOT__s_dq_io = 0U;
                    } else {
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 5U;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe 
                            = (1U | (IData)(vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe));
                    }
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col 
                        = (0x1ffU & ((IData)(1U) + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col)));
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left 
                        = (0x1fU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left) 
                                    - (IData)(1U)));
                    if ((1U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left))) {
                        if (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we) {
                            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__0 = 1U;
                            if ((4U >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))) {
                                vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done 
                                    = (((~ ((IData)(1U) 
                                            << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))) 
                                        & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_done)) 
                                       | (0x1fU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h7fb74084__0) 
                                                   << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant))));
                            }
                            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard = 2U;
                            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 4U;
                        } else {
                            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 3U;
                            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 8U;
                        }
                    } else if (((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we)) 
                                & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant)))) {
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 7U;
                    }
                }
            } else if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 6U;
                }
            } else if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_due) 
                     & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard)))) {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 2U;
                    vlSelf->tb_ram_dma_fill__DOT__s_a = 0x400U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt = 0U;
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open = 0U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 9U;
                } else if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__have_req) 
                            & (~ ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_miss) 
                                  & (0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard)))))) {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h53139d90__0 = 1U;
                    if ((0x77U >= (0x7fU & ((IData)(0x18U) 
                                            * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))) {
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
                            = (0xffffffU & (((0U == 
                                              (0x1fU 
                                               & ((IData)(0x18U) 
                                                  * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))
                                              ? 0U : 
                                             (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                                              (((IData)(0x17U) 
                                                + (0x7fU 
                                                   & ((IData)(0x18U) 
                                                      * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))) 
                                               >> 5U)] 
                                              << ((IData)(0x20U) 
                                                  - 
                                                  (0x1fU 
                                                   & ((IData)(0x18U) 
                                                      * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))) 
                                            | (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                                               (3U 
                                                & (((IData)(0x18U) 
                                                    * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)) 
                                                   >> 5U))] 
                                               >> (0x1fU 
                                                   & ((IData)(0x18U) 
                                                      * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))));
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col 
                            = (0x1ffU & (((0U == (0x1fU 
                                                  & ((IData)(0x18U) 
                                                     * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))
                                           ? 0U : (
                                                   vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                                                   (((IData)(8U) 
                                                     + 
                                                     (0x7fU 
                                                      & ((IData)(0x18U) 
                                                         * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))) 
                                                    >> 5U)] 
                                                   << 
                                                   ((IData)(0x20U) 
                                                    - 
                                                    (0x1fU 
                                                     & ((IData)(0x18U) 
                                                        * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)))))) 
                                         | (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[
                                            (3U & (
                                                   ((IData)(0x18U) 
                                                    * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)) 
                                                   >> 5U))] 
                                            >> (0x1fU 
                                                & ((IData)(0x18U) 
                                                   * (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))))));
                    } else {
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr = 0U;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col = 0U;
                    }
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we 
                        = ((4U >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner)) 
                           && (1U & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r) 
                                     >> (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))));
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left 
                        = (0x1fU & ((IData)(1U) + (
                                                   (0x13U 
                                                    >= 
                                                    (0x1fU 
                                                     & VL_SHIFTL_III(5,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner), 2U)))
                                                    ? 
                                                   (0xfU 
                                                    & ((0x8000U 
                                                        | (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r)) 
                                                       >> 
                                                       (0x1fU 
                                                        & VL_SHIFTL_III(5,32,32, (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner), 2U))))
                                                    : 0U)));
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant 
                        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner;
                    if ((4U >= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))) {
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack 
                            = (((~ ((IData)(1U) << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))) 
                                & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_ack)) 
                               | (0x1fU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____Vlvbound_h53139d90__0) 
                                           << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))));
                    }
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt = 0U;
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rr_ptr 
                        = ((4U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))
                            ? 0U : (7U & ((IData)(1U) 
                                          + (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__winner))));
                    if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h1ea43d0e__0) 
                         & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT____VdfgTmp_h44e2fdf7__0) 
                            == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row)))) {
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 6U;
                    } else if (((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_miss) 
                                & (0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard)))) {
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 2U;
                        vlSelf->tb_ram_dma_fill__DOT__s_ba 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank;
                        vlSelf->tb_ram_dma_fill__DOT__s_a = 0U;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open 
                            = ((~ ((IData)(1U) << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank))) 
                               & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open));
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 0xbU;
                    } else {
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 3U;
                        vlSelf->tb_ram_dma_fill__DOT__s_a 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row;
                        vlSelf->tb_ram_dma_fill__DOT__s_ba 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank;
                        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open 
                            = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__row_open) 
                               | (0xfU & ((IData)(1U) 
                                          << (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank))));
                        __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_row;
                        vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 = 1U;
                        __Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1 
                            = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__act_bank;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
                        vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 5U;
                    }
                }
            }
        } else if ((2U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
            if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
                if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__init_done = 1U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt = 0U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 4U;
                }
            } else if ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer))) {
                if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left))) {
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left 
                        = (0xffffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left) 
                                      - (IData)(1U)));
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 1U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 4U;
                } else {
                    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 0U;
                    vlSelf->tb_ram_dma_fill__DOT__s_a = 0x20U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
                    vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 3U;
                }
            }
        } else if ((1U & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state))) {
            vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cmd = 2U;
            vlSelf->tb_ram_dma_fill__DOT__s_a = 0x400U;
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer = 2U;
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left = 8U;
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 2U;
        } else if ((0U != (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left))) {
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left 
                = (0xffffU & ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left) 
                              - (IData)(1U)));
        } else {
            vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state = 1U;
        }
        if ((4U & (IData)(vlSelf->tb_ram_dma_fill__DOT__dack_n))) {
            if (vlSelf->tb_ram_dma_fill__DOT__want_drq) {
                vlSelf->tb_ram_dma_fill__DOT__dreq 
                    = (4U | (IData)(vlSelf->tb_ram_dma_fill__DOT__dreq));
            }
        } else {
            vlSelf->tb_ram_dma_fill__DOT__dreq = (0xbU 
                                                  & (IData)(vlSelf->tb_ram_dma_fill__DOT__dreq));
        }
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__init_left;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__left;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_we;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_col;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__pre_guard;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__rd_pipe;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_grant;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt;
    if (vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row[__Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v0;
    }
    if (vlSelf->__Vdlyvset__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1) {
        vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row[__Vdlyvdim0__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1] 
            = __Vdlyvval__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__open_row__v1;
    }
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__timer;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__state;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_bank 
        = (3U & (vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__cur_addr 
                 >> 9U));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_due 
        = (0x140U <= (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__u_mp__DOT__refresh_cnt));
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_sequent__TOP__3(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_sequent__TOP__3\n"); );
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_rdata 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset)
            ? 0U : ((IData)(vlSelf->tb_ram_dma_fill__DOT__dq_in__en0) 
                    & (((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT____VdfgTmp_h854dc19a__0)
                         ? ((5U >= (7U & (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat 
                                          - (IData)(1U))))
                             ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
                            [(7U & (vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat 
                                    - (IData)(1U)))]
                             : 0U) : ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold1)
                                       ? ((5U >= (7U 
                                                  & vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat))
                                           ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
                                          [(7U & vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat)]
                                           : 0U) : 
                                      ((IData)(vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__hold2)
                                        ? ((5U >= (7U 
                                                   & ((IData)(1U) 
                                                      + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat)))
                                            ? vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__rd_data
                                           [(7U & ((IData)(1U) 
                                                   + vlSelf->tb_ram_dma_fill__DOT__sdr__DOT__cas_lat))]
                                            : 0U) : 0U))) 
                       & (IData)(vlSelf->tb_ram_dma_fill__DOT__dq_in__en0))));
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_sequent__TOP__4(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_sequent__TOP__4\n"); );
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__len_r;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r 
        = vlSelf->__Vdly__tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r;
    vlSelf->tb_ram_dma_fill__DOT__dack_n = (0xfU & 
                                            ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dack_sense_active_high)
                                              ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff)
                                              : (~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_dmac__DOT__u_Timing_And_Control__DOT__dma_acknowledge_ff))));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__write_flag 
        = ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__read_flag 
        = ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__we_r)) 
           & (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__busy));
}

VL_INLINE_OPT void Vtb_ram_dma_fill___024root___nba_comb__TOP__2(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___nba_comb__TOP__2\n"); );
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
    // Body
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[0U] 
        = vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__addr_r;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[2U] = 0xa00000U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_addr[3U] 
        = (0xffffffU & vlSelf->tb_ram_dma_fill__DOT__ri_addr);
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[0U] 
        = ((0U == (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wcnt))
            ? (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_r)
            : (IData)(vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__wdata_hi_r));
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[1U] = 0U;
    vlSelf->tb_ram_dma_fill__DOT__u_ram__DOT__u_sdram__DOT__mp_wdata[2U] = 0U;
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
    vlSelf->tb_ram_dma_fill__DOT__bus_addr = (((~ (IData)(
                                                          (0xfU 
                                                           == (IData)(vlSelf->tb_ram_dma_fill__DOT__dack_n)))) 
                                               & ((IData)(vlSelf->tb_ram_dma_fill__DOT__aen_n) 
                                                  & (IData)(vlSelf->tb_ram_dma_fill__DOT__dma_wait)))
                                               ? (IData)(vlSelf->tb_ram_dma_fill__DOT__dmac_addr_out)
                                               : vlSelf->tb_ram_dma_fill__DOT__bench_addr);
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

void Vtb_ram_dma_fill___024root___eval_nba(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_nba\n"); );
    // Body
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_sequent__TOP__0(vlSelf);
    }
    if ((4ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_sequent__TOP__1(vlSelf);
    }
    if ((6ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_comb__TOP__0(vlSelf);
    }
    if ((2ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_sequent__TOP__2(vlSelf);
    }
    if ((8ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_sequent__TOP__3(vlSelf);
    }
    if ((5ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___act_sequent__TOP__0(vlSelf);
    }
    if ((4ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_sequent__TOP__4(vlSelf);
    }
    if ((6ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vtb_ram_dma_fill___024root___nba_comb__TOP__2(vlSelf);
    }
}

void Vtb_ram_dma_fill___024root___timing_commit(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___timing_commit\n"); );
    // Body
    if ((! (2ULL & vlSelf->__VactTriggered.word(0U)))) {
        vlSelf->__VtrigSched_hff9fd67f__0.commit("@(posedge tb_ram_dma_fill.clk)");
    }
}

void Vtb_ram_dma_fill___024root___timing_resume(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___timing_resume\n"); );
    // Body
    if ((2ULL & vlSelf->__VactTriggered.word(0U))) {
        vlSelf->__VtrigSched_hff9fd67f__0.resume("@(posedge tb_ram_dma_fill.clk)");
    }
    if ((0x10ULL & vlSelf->__VactTriggered.word(0U))) {
        vlSelf->__VdlySched.resume();
    }
}

void Vtb_ram_dma_fill___024root___eval_triggers__act(Vtb_ram_dma_fill___024root* vlSelf);

bool Vtb_ram_dma_fill___024root___eval_phase__act(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_phase__act\n"); );
    // Init
    VlTriggerVec<5> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vtb_ram_dma_fill___024root___eval_triggers__act(vlSelf);
    Vtb_ram_dma_fill___024root___timing_commit(vlSelf);
    __VactExecute = vlSelf->__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelf->__VactTriggered, vlSelf->__VnbaTriggered);
        vlSelf->__VnbaTriggered.thisOr(vlSelf->__VactTriggered);
        Vtb_ram_dma_fill___024root___timing_resume(vlSelf);
        Vtb_ram_dma_fill___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vtb_ram_dma_fill___024root___eval_phase__nba(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_phase__nba\n"); );
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelf->__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vtb_ram_dma_fill___024root___eval_nba(vlSelf);
        vlSelf->__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__nba(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__act(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG

void Vtb_ram_dma_fill___024root___eval(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval\n"); );
    // Init
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vtb_ram_dma_fill___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("/work/sim/tb_ram_dma_fill.sv", 32, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelf->__VactIterCount = 0U;
        vlSelf->__VactContinue = 1U;
        while (vlSelf->__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelf->__VactIterCount))) {
#ifdef VL_DEBUG
                Vtb_ram_dma_fill___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("/work/sim/tb_ram_dma_fill.sv", 32, "", "Active region did not converge.");
            }
            vlSelf->__VactIterCount = ((IData)(1U) 
                                       + vlSelf->__VactIterCount);
            vlSelf->__VactContinue = 0U;
            if (Vtb_ram_dma_fill___024root___eval_phase__act(vlSelf)) {
                vlSelf->__VactContinue = 1U;
            }
        }
        if (Vtb_ram_dma_fill___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vtb_ram_dma_fill___024root___eval_debug_assertions(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_debug_assertions\n"); );
}
#endif  // VL_DEBUG
