print("Lua Counter test start")
local signals = list_signals()
for k,v in pairs(signals.inputs) do print("input", k,v) end
for k,v in pairs(signals.outputs) do print("output", k,v) end

local i = 0
print("Running")
while not is_finished() do
	set_signal(signals.inputs.clk, 1)
	eval()
	set_signal(signals.inputs.clk, 0)
	eval()
	local cnt = get_signal(signals.outputs.cnt)
	print("cnt value in Lua:", cnt)
	if i == 1000 then break end
	i = i + 1
end
print("End")