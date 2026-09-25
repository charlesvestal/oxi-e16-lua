/*
 * e16host: approximates the OXI E16 Lua environment to measure real heap use.
 *
 *  - Lua 5.4 built with LUA_32BITS (the firmware uses 32-bit float numbers)
 *  - build for a 32-bit target so pointers/TValues match Cortex-M
 *  - allocator models FreeRTOS heap_4 (the firmware's allocator):
 *    8-byte block header, sizes rounded up to 8 bytes
 *  - only base, math, string and table libraries (what the firmware opens)
 *  - generational GC (firmware calls lua_gc(L, LUA_GCGEN))
 *  - stub API tables: page, controller, midi, leds, slots, var, system
 *
 * usage: e16host script.lua [seconds-of-playback] [heap-cap-bytes]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

static size_t cur, peak, nblocks, cap;   /* cap: optional heap limit (0 = none) */

static size_t cost(size_t n) { return n ? ((n + 8 + 7) & ~(size_t)7) : 0; }

static void *alloc(void *ud, void *p, size_t osize, size_t nsize) {
  (void)ud;
  if (p) { cur -= cost(osize); nblocks--; }
  if (nsize == 0) { free(p); return NULL; }
  if (cap && cur + cost(nsize) > cap) {        /* simulate running out of heap */
    if (p) { cur += cost(osize); nblocks++; }
    return NULL;
  }
  void *q = realloc(p, nsize);
  if (!q) { if (p) { cur += cost(osize); nblocks++; } return NULL; }
  cur += cost(nsize); nblocks++;
  if (cur > peak) peak = cur;
  return q;
}

static int noop(lua_State *L) { (void)L; return 0; }
static int getpage(lua_State *L) { lua_pushinteger(L, 1); return 1; }

/* var store: up to 32 entries, lives outside the Lua heap like the firmware's */
static struct { char name[17]; int type; float f; int i; } vars[32];
static int nvars;
static int findvar(const char *n) {
  for (int k = 0; k < nvars; k++) if (!strcmp(vars[k].name, n)) return k;
  return -1;
}
static int var_register(lua_State *L) {
  const char *n = luaL_checkstring(L, 1);
  const char *t = luaL_checkstring(L, 2);
  if (findvar(n) >= 0 || nvars >= 32) return 0;
  strncpy(vars[nvars].name, n, 16);
  vars[nvars].type = t[0] == 'i' ? 1 : t[0] == 'b' ? 2 : 3;
  if (vars[nvars].type == 2) vars[nvars].i = lua_toboolean(L, 3);
  else if (vars[nvars].type == 1) vars[nvars].i = (int)luaL_checknumber(L, 3);
  else vars[nvars].f = (float)luaL_checknumber(L, 3);
  nvars++;
  return 0;
}
static int var_get(lua_State *L) {
  int k = findvar(luaL_checkstring(L, 1));
  if (k < 0) { lua_pushnil(L); return 1; }
  if (vars[k].type == 1) lua_pushinteger(L, vars[k].i);
  else if (vars[k].type == 2) lua_pushboolean(L, vars[k].i);
  else lua_pushnumber(L, vars[k].f);
  return 1;
}
static int var_set(lua_State *L) {
  int k = findvar(luaL_checkstring(L, 1));
  if (k < 0) return 0;
  if (vars[k].type == 2) vars[k].i = lua_toboolean(L, 2);
  else if (vars[k].type == 1) vars[k].i = (int)luaL_checknumber(L, 2);
  else vars[k].f = (float)luaL_checknumber(L, 2);
  return 0;
}
static int setrate(lua_State *L) { (void)L; return 0; }

static void lib(lua_State *L, const char *name, const luaL_Reg *r) {
  lua_newtable(L);
  luaL_setfuncs(L, r, 0);
  lua_setglobal(L, name);
}

static int call(lua_State *L, const char *tbl, const char *fn, int nargs) {
  lua_getglobal(L, tbl);
  lua_getfield(L, -1, fn);
  lua_remove(L, -2);
  if (lua_type(L, -1) != LUA_TFUNCTION) { lua_pop(L, 1); return 0; }
  if (lua_pcall(L, nargs, 0, 0) != LUA_OK) {
    fprintf(stderr, "error in %s.%s: %s\n", tbl, fn, lua_tostring(L, -1));
    fprintf(stderr, "at failure: Lua count %.1f KB, heap in use %zu B (cap %zu B)\n",
            lua_gc(L, LUA_GCCOUNT) + lua_gc(L, LUA_GCCOUNTB) / 1024.0, cur, cap);
    exit(1);
  }
  return 1;
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: e16host script.lua [seconds]\n"); return 2; }
  int secs = argc > 2 ? atoi(argv[2]) : 30;
  cap = argc > 3 ? (size_t)atol(argv[3]) : 0;
  lua_State *L = lua_newstate(alloc, NULL);
  lua_gc(L, LUA_GCGEN, 0, 0);
  luaL_requiref(L, "_G", luaopen_base, 1); lua_pop(L, 1);
  luaL_requiref(L, "math", luaopen_math, 1); lua_pop(L, 1);
  luaL_requiref(L, "string", luaopen_string, 1); lua_pop(L, 1);
  luaL_requiref(L, "table", luaopen_table, 1); lua_pop(L, 1);
  lua_gc(L, LUA_GCCOLLECT);
  size_t vm = cur;

  const luaL_Reg page[] = {{"setTitle", noop}, {"resetTitle", noop}, {NULL, NULL}};
  const luaL_Reg ctl[] = {{"set", noop}, {"setByIndex", noop}, {"setControls", noop}, {"getPage", getpage}, {NULL, NULL}};
  const luaL_Reg midi[] = {{"sendCC", noop}, {"sendPC", noop}, {"sendSysex", noop}, {"sendMidi", noop}, {NULL, NULL}};
  const luaL_Reg leds[] = {{"update", noop}, {"updateByIndex", noop}, {"reset", noop}, {"resetById", noop}, {NULL, NULL}};
  const luaL_Reg slots[] = {{"update", noop}, {"reset", noop}, {NULL, NULL}};
  const luaL_Reg var[] = {{"register", var_register}, {"get", var_get}, {"set", var_set}, {"delete", noop}, {"deleteAll", noop}, {NULL, NULL}};
  const luaL_Reg sys[] = {{"setUpdateRate", setrate}, {NULL, NULL}};
  lib(L, "page", page); lib(L, "controller", ctl); lib(L, "midi", midi);
  lib(L, "leds", leds); lib(L, "slots", slots); lib(L, "var", var); lib(L, "system", sys);
  lua_gc(L, LUA_GCCOLLECT);
  size_t base = cur;

  peak = cur;
  if (luaL_loadfile(L, argv[1]) != LUA_OK) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  if (lua_pcall(L, 0, 0, 0) != LUA_OK) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  size_t loadpeak = peak;
  call(L, "page", "onInit", 0);
  lua_gc(L, LUA_GCCOLLECT);
  size_t live = cur;

  /* start the transport (push id 19 = Play/Stop) and run updates */
  lua_getglobal(L, "controller"); lua_getfield(L, -1, "onEncoderPress"); lua_remove(L, -2);
  if (!lua_isfunction(L, -1)) lua_pushcfunction(L, noop), lua_replace(L, -2);
  lua_createtable(L, 0, 5);
  lua_pushinteger(L, 19); lua_setfield(L, -2, "id");
  lua_pushinteger(L, 3); lua_setfield(L, -2, "index");
  lua_pushinteger(L, 1); lua_setfield(L, -2, "page");
  lua_pcall(L, 1, 0, 0);
  peak = cur;
  for (int i = 0; i < secs * 50; i++) call(L, "system", "update", 0);
  /* some encoder turns while playing */
  for (int id = 1; id <= 16; id++) {
    lua_getglobal(L, "controller"); lua_getfield(L, -1, "onEncoderTurn"); lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) lua_pushcfunction(L, noop), lua_replace(L, -2);
    lua_createtable(L, 0, 6);
    lua_pushinteger(L, id); lua_setfield(L, -2, "id");
    lua_pushinteger(L, id); lua_setfield(L, -2, "index");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "page");
    lua_pushinteger(L, 1); lua_setfield(L, -2, "increment");
    lua_pushinteger(L, 8192); lua_setfield(L, -2, "value");
    lua_pushinteger(L, 64); lua_setfield(L, -2, "scaled");
    lua_pushboolean(L, 0); lua_setfield(L, -2, "is_held");
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) { fprintf(stderr, "%s\n", lua_tostring(L, -1)); return 1; }
  }
  size_t runpeak = peak;

  printf("VM + std libs         %6zu B\n", vm);
  printf("E16 API tables        %6zu B\n", base - vm);
  printf("script peak (load)    %6zu B\n", loadpeak - base);
  printf("script live (init)    %6zu B\n", live - base);
  printf("script peak (playing) %6zu B\n", runpeak - base);
  printf("TOTAL live            %6zu B   (%zu blocks)\n", live, nblocks);
  lua_close(L);
  return 0;
}
