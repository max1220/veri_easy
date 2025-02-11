# veri_easy

`Easy verilog build and test tool using bash, Lua, and C++`

This repository contains a simple build script that takes in a verilog file,
extracts inputs/outputs using verilators's `--xml-only` option and `xmlstarlet`,
parses them in bash, generates a simple C++ main file that embeds a Lua
interpreter to control the verilated model, and then compiles a
complete binary using verilator, containing the Lua interpreter.


## Usage

```
./build_and_run <verilog module>
./build_and_run <verilog module> <lua script file>
```

The generated binary supports a single argument, and can be used like this:
```
./obj_dir/V<verilog module> <lua script file>
```

If no `<lua script file>` is provided you will be dropped to an interactive
Lua debug prompt.

The Lua environment the script runs in has 4 global functions to interact with the model:


### io = list_signals()

Returns a table associating signal names with signal IDs, e.g. `io.inputs.clk`, `io.outputs.cnt`

### n = get_signal(signal_id)

Gets the current value for the specified `signal_id`.

### set_signal(signal_id, value)

Sets the current value for the specified `signal_id`.

### eval()

Evaluate the model

### is_finished()

Returns true if the model finished.
