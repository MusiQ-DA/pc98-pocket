//
// np21w compat shim -- pccore.h, reduced to the one type the golden engine
// signatures name: NP2CFG (egc_reset takes it and ignores it).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef NP21W_SHIM_PCCORE_H
#define NP21W_SHIM_PCCORE_H

typedef struct tagNP2Config {
	int	dummy;
} NP2CFG;

#endif	// NP21W_SHIM_PCCORE_H
