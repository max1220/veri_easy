#!/bin/bash
set -euo pipefail

# name of the top module(filename must match as well!)
TOP_MODULE="$(basename -s .v "${1}")"
shift

# Generate XML representation
echo -e "\e[33m --- Generating XML ---\e[0m"
verilator --xml-only --top "${TOP_MODULE}" "${TOP_MODULE}.v"

# re-format the XML with the -R(recover) option set, to allow parsing
# even if a single string contains a &#27;, which is generated by verilator :/
xmlstarlet format -R "obj_dir/V${TOP_MODULE}.xml" > "obj_dir/V${TOP_MODULE}.clean.xml"

# read input/output signal names
readarray -t MODULE_INPUT_NAMES < <(xmlstarlet sel -t -v "//verilator_xml/netlist/module[@topModule='1']/var[@dir='input']/@name" -n "obj_dir/V${TOP_MODULE}.clean.xml")
readarray -t MODULE_OUTPUT_NAMES < <(xmlstarlet sel -t -v "//verilator_xml/netlist/module[@topModule='1']/var[@dir='output']/@name" -n "obj_dir/V${TOP_MODULE}.clean.xml")

echo -e "\e[34m --- Inputs: ---\e[0m"
for i in "${!MODULE_INPUT_NAMES[@]}"; do
	printf "%.3d: \e[34m%s\e[0m\n" "$i" "${MODULE_INPUT_NAMES[$i]}"
done
echo -e "\e[35m --- Opututs: ---\e[0m"
for i in "${!MODULE_OUTPUT_NAMES[@]}"; do
	printf "%.3d: \e[35m%s\e[0m\n" "$i" "${MODULE_OUTPUT_NAMES[$i]}"
done

echo -e "\e[33m --- Generating lua_main.cpp ---\e[0m"

# generate C++ main file from template and input/output signal names
cat << EOF > lua_main.cpp
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

#include <iostream>
#include <memory>
#include "verilated.h"
#include "V${TOP_MODULE}.h"

// Lua-callable function: List supported input/output signals
static int lua_list_signals(lua_State* L) {
	lua_newtable(L);

	lua_pushstring(L, "outputs");
	lua_newtable(L);

$(
	for i in "${!MODULE_OUTPUT_NAMES[@]}"; do
		printf "\tlua_pushstring(L, \"%s\"); " "${MODULE_OUTPUT_NAMES[$i]}"
		printf "\tlua_pushinteger(L, %d); " "$i"
		printf "\tlua_settable(L, -3);\n"
	done
)

	lua_settable(L, -3);
	
	lua_pushstring(L, "inputs");
	lua_newtable(L);

$(
	for i in "${!MODULE_INPUT_NAMES[@]}"; do
		printf "\tlua_pushstring(L, \"%s\"); " "${MODULE_INPUT_NAMES[$i]}"
		printf "\tlua_pushinteger(L, %d); " "$i"
		printf "\tlua_settable(L, -3);\n"
	done
)

	lua_settable(L, -3);

	return 1;
}

// Lua-callable function: Get signal value
static int lua_get_signal(lua_State* L) {
	V${TOP_MODULE}* topp = (V${TOP_MODULE}*)lua_touserdata(L, lua_upvalueindex(1));
	int arg_c = lua_gettop(L);
	for (int arg_i=1; arg_i<=arg_c; arg_i++) {
		int id = luaL_checkinteger(L, arg_i);
		switch(id) {
$(
	for i in "${!MODULE_OUTPUT_NAMES[@]}"; do
		printf "\t\t\tcase %.3d: lua_pushinteger(L, topp->%s); break;\n" "$i" "${MODULE_OUTPUT_NAMES[$i]}"
	done
)
			default: lua_pushnil(L);
		}
	}
	return arg_c;
}

// Lua-callable function: Set signal value
static int lua_set_signal(lua_State* L) {
	V${TOP_MODULE}* topp = (V${TOP_MODULE}*)lua_touserdata(L, lua_upvalueindex(1));
	int id = luaL_checkinteger(L, 1);
	int value = luaL_checkinteger(L, 2);
	switch(id) {
$(
	for i in "${!MODULE_INPUT_NAMES[@]}"; do
		printf "\t\tcase %.3d: topp->%s = value; break; \n" "$i" "${MODULE_INPUT_NAMES[$i]}"
	done
)
		default: lua_pushnil(L); return 1;
	}
	lua_pushboolean(L, 1);
	return 1;
}

static int lua_clock_pulse(lua_State *L) {
	V${TOP_MODULE}* topp = (V${TOP_MODULE}*)lua_touserdata(L, lua_upvalueindex(1));
	VerilatedContext* contextp = (VerilatedContext*)lua_touserdata(L, lua_upvalueindex(2));
	int count = luaL_checkinteger(L, 1);
	for (int i=1; i<=count; i++) {
		topp->clk = 1;
		topp->eval();
		contextp->timeInc(1);
		topp->clk = 0;
		topp->eval();
		contextp->timeInc(1);
	}
	return 0;
}

// Lua-callable function: Evaluate the model
static int lua_eval(lua_State* L) {
	V${TOP_MODULE}* topp = (V${TOP_MODULE}*)lua_touserdata(L, lua_upvalueindex(1));
	VerilatedContext* contextp = (VerilatedContext*)lua_touserdata(L, lua_upvalueindex(2));
	topp->eval();
	contextp->timeInc(1);
	return 0;
}

// Lua-callable function: Check if model finished
static int lua_is_finished(lua_State* L) {
	VerilatedContext* contextp = (VerilatedContext*)lua_touserdata(L, lua_upvalueindex(1));
	lua_pushboolean(L, contextp->gotFinish());
	return 1;
}

// Set up Lua environment(4 global C functions: get, set, eval, is_finished)
static void setup_lua_functions(lua_State* L, V${TOP_MODULE}* topp, VerilatedContext* contextp) {
	lua_pushlightuserdata(L, topp);
	lua_pushcclosure(L, lua_list_signals, 1);
	lua_setglobal(L, "list_signals");

	lua_pushlightuserdata(L, topp);
	lua_pushcclosure(L, lua_get_signal, 1);
	lua_setglobal(L, "get_signal");

	lua_pushlightuserdata(L, topp);
	lua_pushcclosure(L, lua_set_signal, 1);
	lua_setglobal(L, "set_signal");

	lua_pushlightuserdata(L, topp);
	lua_pushlightuserdata(L, contextp);
	lua_pushcclosure(L, lua_clock_pulse, 2);
	lua_setglobal(L, "clock_pulse");

	lua_pushlightuserdata(L, topp);
	lua_pushlightuserdata(L, contextp);
	lua_pushcclosure(L, lua_eval, 2);
	lua_setglobal(L, "eval");

	lua_pushlightuserdata(L, contextp);
	lua_pushcclosure(L, lua_is_finished, 1);
	lua_setglobal(L, "is_finished");
}

static void setup_lua_args(lua_State *L, int argc, char** argv) {
	lua_newtable(L);
	for (int i=0; i<argc; i++) {
		lua_pushinteger(L, i);
		lua_pushstring(L, argv[i]);
		lua_settable(L, -3);
	}
	lua_setglobal(L, "arg");
}

// create top-level verilog module and run Lua script
int main(int argc, char** argv, char**) {
	// create verilated model
	Verilated::debug(0);
	std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
	contextp->commandArgs(argc, argv);
	std::unique_ptr<V${TOP_MODULE}> topp{new V${TOP_MODULE}{contextp.get()}};

	// Initialize Lua
	lua_State* L = luaL_newstate();
	luaL_openlibs(L);
	setup_lua_functions(L, topp.get(), contextp.get());
	setup_lua_args(L, argc, argv);

	if (argc == 1) {
		// run Lua interpreter
		std::cerr << "No script provided! Running debug interpreter..." << std::endl;
		luaL_dostring(L, "debug.debug()");
	} else {
		// run script
		if (luaL_dofile(L, argv[1])) {
			std::cerr << "Error: " << lua_tostring(L, -1) << std::endl;
		}
	}

	// Lua script exited
	lua_close(L);
	topp->final();

	return 0;
}
EOF

echo -e "\e[33m --- Building executable ---\e[0m"

# build executable
LUAVER="luajit"
time verilator -j 0 --build --cc --exe lua_main.cpp \
 --assert --pins-sc-biguint --x-initial unique --x-assign unique \
 -CFLAGS "$(pkg-config --cflags "${LUAVER}")" -LDFLAGS "$(pkg-config --libs "${LUAVER}")" \
 --top "${TOP_MODULE}" "${TOP_MODULE}.v"

# run generated executable
if [ -n "${1:-}" ]; then
	echo -e "\e[32m --- Running ---\e[0m"
	"./obj_dir/V${TOP_MODULE}" "${@}"
fi
