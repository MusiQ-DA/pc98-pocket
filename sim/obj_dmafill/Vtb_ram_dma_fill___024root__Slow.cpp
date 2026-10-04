// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_ram_dma_fill.h for the primary calling header

#include "Vtb_ram_dma_fill__pch.h"
#include "Vtb_ram_dma_fill__Syms.h"
#include "Vtb_ram_dma_fill___024root.h"

void Vtb_ram_dma_fill___024root___ctor_var_reset(Vtb_ram_dma_fill___024root* vlSelf);

Vtb_ram_dma_fill___024root::Vtb_ram_dma_fill___024root(Vtb_ram_dma_fill__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vtb_ram_dma_fill___024root___ctor_var_reset(this);
}

void Vtb_ram_dma_fill___024root::__Vconfigure(bool first) {
    if (false && first) {}  // Prevent unused
}

Vtb_ram_dma_fill___024root::~Vtb_ram_dma_fill___024root() {
}
