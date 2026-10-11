//
// np21w compat shim -- compiler.h replacement for the golden harness.
//
// The real np21w compiler.h is platform-specific (x11/win9x/sdl2) and ends by
// including common.h. The three files we compile (mem/memegc.c,
// mem/memvram.c, io/egc.c) need only the type aliases, the endian macros and
// the empty call-convention decorations, so this shim provides exactly those
// and nothing else.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

#ifndef NP21W_SHIM_COMPILER_H
#define NP21W_SHIM_COMPILER_H

#include <stdint.h>
#include <string.h>
#include <stdio.h>

typedef uint8_t		UINT8;
typedef int8_t		SINT8;
typedef uint16_t	UINT16;
typedef int16_t		SINT16;
typedef uint32_t	UINT32;
typedef int32_t		SINT32;
typedef uint64_t	UINT64;
typedef int64_t		SINT64;
typedef unsigned int	UINT;
typedef int		SINT;
typedef int		BOOL;

typedef UINT8		REG8;
typedef UINT16		REG16;
typedef UINT32		REG32;

typedef char		OEMCHAR;

#define	BYTESEX_LITTLE

#define	MEMCALL
#define	IOOUTCALL
#define	IOINPCALL
#define	VRAMCALL
#define	FASTCALL
#define	CPUCALL

#define	TRUE	1
#define	FALSE	0
#define	SUCCESS	0
#define	FAILURE	(-1)

#define	ZeroMemory(p, s)	memset((p), 0, (s))
#define	FillMemory(p, s, v)	memset((p), (v), (s))

#ifndef LOW8
#define	LOW8(a)		((UINT8)(a))
#endif
#ifndef LOW12
#define	LOW12(a)	((a) & 0x0fff)
#endif
#ifndef LOW15
#define	LOW15(a)	((a) & 0x7fff)
#endif
#ifndef LOW16
#define	LOW16(a)	((UINT16)(a))
#endif
#ifndef HIGH16
#define	HIGH16(a)	(((UINT32)(a)) >> 16)
#endif

// common.h's x86-order helpers; BYTESEX_LITTLE host, so these are the
// straight byte forms np21w uses for the little-endian build.
#ifndef LOADINTELWORD
#define	LOADINTELWORD(a) \
	(((UINT16)((UINT8*)(a))[0]) | ((UINT16)(((UINT8*)(a))[1]) << 8))
#endif
#ifndef LOADINTELDWORD
#define	LOADINTELDWORD(a) \
	(((UINT32)((UINT8*)(a))[0])        | ((UINT32)(((UINT8*)(a))[1]) << 8) | \
	 ((UINT32)((UINT8*)(a))[2] << 16) | ((UINT32)(((UINT8*)(a))[3]) << 24))
#endif
#ifndef STOREINTELWORD
#define	STOREINTELWORD(a, b) \
	*(((UINT8*)(a))+0) = (UINT8)((b)); \
	*(((UINT8*)(a))+1) = (UINT8)(((b) >> 8))
#endif
#ifndef STOREINTELDWORD
#define	STOREINTELDWORD(a, b) \
	*(((UINT8*)(a))+0) = (UINT8)((b)); \
	*(((UINT8*)(a))+1) = (UINT8)(((b) >> 8)); \
	*(((UINT8*)(a))+2) = (UINT8)(((b) >> 16)); \
	*(((UINT8*)(a))+3) = (UINT8)(((b) >> 24))
#endif

#ifndef __ASSERT
#define	__ASSERT(x)	((void)0)
#endif

#define	TRACEOUT(port, val)		((void)0)
#define	TRACEOUTW(port, val)	((void)0)

#endif	// NP21W_SHIM_COMPILER_H
