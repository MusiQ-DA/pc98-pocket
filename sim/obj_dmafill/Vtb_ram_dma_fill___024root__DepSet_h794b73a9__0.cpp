// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_ram_dma_fill.h for the primary calling header

#include "Vtb_ram_dma_fill__pch.h"
#include "Vtb_ram_dma_fill__Syms.h"
#include "Vtb_ram_dma_fill___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__act(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG

void Vtb_ram_dma_fill___024root___eval_triggers__act(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_triggers__act\n"); );
    // Body
    vlSelf->__VactTriggered.set(0U, ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num) 
                                     != (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__1)));
    vlSelf->__VactTriggered.set(1U, ((IData)(vlSelf->tb_ram_dma_fill__DOT__clk) 
                                     & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0))));
    vlSelf->__VactTriggered.set(2U, (((IData)(vlSelf->tb_ram_dma_fill__DOT__clk) 
                                      & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0))) 
                                     | ((IData)(vlSelf->tb_ram_dma_fill__DOT__reset) 
                                        & (~ (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__reset__0)))));
    vlSelf->__VactTriggered.set(3U, ((~ (IData)(vlSelf->tb_ram_dma_fill__DOT__clk)) 
                                     & (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0)));
    vlSelf->__VactTriggered.set(4U, vlSelf->__VdlySched.awaitingCurrentTime());
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__1 
        = vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__clk__0 
        = vlSelf->tb_ram_dma_fill__DOT__clk;
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__reset__0 
        = vlSelf->tb_ram_dma_fill__DOT__reset;
    if (VL_UNLIKELY((1U & (~ (IData)(vlSelf->__VactDidInit))))) {
        vlSelf->__VactDidInit = 1U;
        vlSelf->__VactTriggered.set(0U, 1U);
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_ram_dma_fill___024root___dump_triggers__act(vlSelf);
    }
#endif
}
