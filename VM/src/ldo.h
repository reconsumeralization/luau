// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lobject.h"
#include "lstate.h"
#include "luaconf.h"
#include "ldebug.h"

// returns target stack for 'n' extra elements to reallocate
// if possible, stack size growth factor is 2x
#define getgrownstacksize(L, n) ((n) <= L->stacksize ? 2 * L->stacksize : L->stacksize + (n))
#define stacklimitreached(L, n) ((char*)L->stack_last - (char*)L->top <= (n) * (int)sizeof(TValue))

#define luaD_checkstackfornewci(L, n) \
    if (stacklimitreached(L, (n))) \
        luaD_reallocstack(L, getgrownstacksize(L, (n)), 1); \
    else \
        condhardstacktests(luaD_reallocstack(L, L->stacksize - EXTRA_STACK, 1));

#define luaD_checkstack(L, n) \
    if (stacklimitreached(L, (n))) \
        luaD_growstack(L, n); \
    else \
        condhardstacktests(luaD_reallocstack(L, L->stacksize - EXTRA_STACK, 0));

#define incr_top(L) \
    { \
        luaD_checkstack(L, 1); \
        L->top++; \
    }

#define savestack(L, p) ((char*)(p) - (char*)L->stack)
#define restorestack(L, n) ((TValue*)((char*)L->stack + (n)))

#define expandstacklimit(L, p) \
    { \
        LUAU_ASSERT((p) <= (L)->stack_last); \
        if ((L)->ci->top < (p)) \
            (L)->ci->top = (p); \
    }

#define incr_ci(L) ((L->ci == L->end_ci) ? luaD_growCI(L) : (condhardstacktests(luaD_reallocCI(L, L->size_ci)), ++L->ci))

#define saveci(L, p) ((char*)(p) - (char*)L->base_ci)
#define restoreci(L, n) ((CallInfo*)((char*)L->base_ci + (n)))

// results from luaD_precall
#define PCRLUA 0   // initiated a call to a Lua function
#define PCRC 1     // did a call to a C function
#define PCRYIELD 2 // C function yielded

// type of protected functions, to be ran by `runprotected'
typedef void (*Pfunc)(lua_State* L, void* ud);

LUAI_FUNC CallInfo* luaD_growCI(lua_State* L);

LUAI_FUNC void luaD_call(lua_State* L, StkId func, int nresults);
LUAI_FUNC void luaD_callny(lua_State* L, StkId func, int nresults);
LUAI_FUNC int luaD_pcall(lua_State* L, Pfunc func, void* u, ptrdiff_t oldtop, ptrdiff_t ef);
LUAI_FUNC void luaD_reallocCI(lua_State* L, int newsize);
LUAI_FUNC void luaD_reallocstack(lua_State* L, int newsize, int fornewci);
LUAI_FUNC void luaD_growstack(lua_State* L, int n);
LUAI_FUNC void luaD_checkCstack(lua_State* L);

LUAI_FUNC l_noret luaD_throw(lua_State* L, int errcode);
LUAI_FUNC int luaD_rawrunprotected(lua_State* L, Pfunc f, void* ud);
