// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_ram_dma_fill.h for the primary calling header

#include "Vtb_ram_dma_fill__pch.h"
#include "Vtb_ram_dma_fill__Syms.h"
#include "Vtb_ram_dma_fill___024root.h"

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_ram_dma_fill___024root___dump_triggers__stl(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtb_ram_dma_fill___024root___eval_triggers__stl(Vtb_ram_dma_fill___024root* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtb_ram_dma_fill__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_ram_dma_fill___024root___eval_triggers__stl\n"); );
    // Body
    vlSelf->__VstlTriggered.set(0U, (IData)(vlSelf->__VstlFirstIteration));
    vlSelf->__VstlTriggered.set(1U, ((IData)(vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num) 
                                     != (IData)(vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__0)));
    vlSelf->__Vtrigprevexpr___TOP__tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num__0 
        = vlSelf->tb_ram_dma_fill__DOT__u_ce__DOT__cpu_edge_num;
    if (VL_UNLIKELY((1U & (~ (IData)(vlSelf->__VstlDidInit))))) {
        vlSelf->__VstlDidInit = 1U;
        vlSelf->__VstlTriggered.set(1U, 1U);
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_ram_dma_fill___024root___dump_triggers__stl(vlSelf);
    }
#endif
}
