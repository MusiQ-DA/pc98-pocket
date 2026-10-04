// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vtb_ram_dma_fill__pch.h"

//============================================================
// Constructors

Vtb_ram_dma_fill::Vtb_ram_dma_fill(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vtb_ram_dma_fill__Syms(contextp(), _vcname__, this)}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vtb_ram_dma_fill::Vtb_ram_dma_fill(const char* _vcname__)
    : Vtb_ram_dma_fill(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vtb_ram_dma_fill::~Vtb_ram_dma_fill() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vtb_ram_dma_fill___024root___eval_debug_assertions(Vtb_ram_dma_fill___024root* vlSelf);
#endif  // VL_DEBUG
void Vtb_ram_dma_fill___024root___eval_static(Vtb_ram_dma_fill___024root* vlSelf);
void Vtb_ram_dma_fill___024root___eval_initial(Vtb_ram_dma_fill___024root* vlSelf);
void Vtb_ram_dma_fill___024root___eval_settle(Vtb_ram_dma_fill___024root* vlSelf);
void Vtb_ram_dma_fill___024root___eval(Vtb_ram_dma_fill___024root* vlSelf);

void Vtb_ram_dma_fill::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vtb_ram_dma_fill::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vtb_ram_dma_fill___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vtb_ram_dma_fill___024root___eval_static(&(vlSymsp->TOP));
        Vtb_ram_dma_fill___024root___eval_initial(&(vlSymsp->TOP));
        Vtb_ram_dma_fill___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vtb_ram_dma_fill___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vtb_ram_dma_fill::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty(); }

uint64_t Vtb_ram_dma_fill::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* Vtb_ram_dma_fill::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vtb_ram_dma_fill___024root___eval_final(Vtb_ram_dma_fill___024root* vlSelf);

VL_ATTR_COLD void Vtb_ram_dma_fill::final() {
    Vtb_ram_dma_fill___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vtb_ram_dma_fill::hierName() const { return vlSymsp->name(); }
const char* Vtb_ram_dma_fill::modelName() const { return "Vtb_ram_dma_fill"; }
unsigned Vtb_ram_dma_fill::threads() const { return 1; }
void Vtb_ram_dma_fill::prepareClone() const { contextp()->prepareClone(); }
void Vtb_ram_dma_fill::atClone() const {
    contextp()->threadPoolpOnClone();
}

//============================================================
// Trace configuration

VL_ATTR_COLD void Vtb_ram_dma_fill::trace(VerilatedVcdC* tfp, int levels, int options) {
    vl_fatal(__FILE__, __LINE__, __FILE__,"'Vtb_ram_dma_fill::trace()' called on model that was Verilated without --trace option");
}
