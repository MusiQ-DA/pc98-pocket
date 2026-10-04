// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VTB_RAM_DMA_FILL__SYMS_H_
#define VERILATED_VTB_RAM_DMA_FILL__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vtb_ram_dma_fill.h"

// INCLUDE MODULE CLASSES
#include "Vtb_ram_dma_fill___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES)Vtb_ram_dma_fill__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vtb_ram_dma_fill* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vtb_ram_dma_fill___024root     TOP;

    // CONSTRUCTORS
    Vtb_ram_dma_fill__Syms(VerilatedContext* contextp, const char* namep, Vtb_ram_dma_fill* modelp);
    ~Vtb_ram_dma_fill__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
