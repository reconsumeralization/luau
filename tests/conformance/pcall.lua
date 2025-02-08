-- This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
print("testing pcall")

function checkresults(e, ...)
	local t = table.pack(...)
	assert(t.n == #e)
	for i=1,t.n do
		assert(t[i] == e[i])
	end
end

function checkerror(...)
	local t = table.pack(...)
	assert(t.n == 2)
	assert(t[1] == false)
	assert(type(t[2]) == "string")
end

function corun(f)
	local co = coroutine.create(f)
	local res = {}
	while coroutine.status(co) == "suspended" do
		res = {coroutine.resume(co)}
	end
	assert(coroutine.status(co) == "dead")
	return table.unpack(res)
end

function colog(f)
	local co = coroutine.create(f)
	local res = {}
	while coroutine.status(co) == "suspended" do
		local run = {coroutine.resume(co)}
		if run[1] then
			table.insert(res, coroutine.status(co) == "suspended" and "yield" or "return");
		else
			table.insert(res, "error");
		end
		table.move(run, 2, #run, 1 + #res, res) -- equivalent to table.append(res, run)
		print(coroutine.status(co), table.unpack(res))
	end
	assert(coroutine.status(co) == "dead")
	return table.unpack(res)
end

-- basic behavior tests - no error/yielding, just checking argument passing
checkresults({ true, 42 }, pcall(function() return 42 end))
checkresults({ true, 1, 2, 42 }, pcall(function(a, b) return a, b, 42 end, 1, 2))
checkresults({ true, 2 }, pcall(function(...) return select('#', ...) end, 1, 2))

-- the argument could be a C function or a callable
checkresults({ true, 42 }, pcall(math.abs, -42))
checkresults({ true, 42 }, pcall(setmetatable({}, { __call = function(self, arg) return math.abs(arg) end }), -42))

-- basic error tests - including interpreter errors and errors generated by C APIs
checkerror(pcall(function() local a = nil / 5 end))
checkerror(pcall(function() select(-100) end))

if not limitedstack then
	-- complex error tests - stack overflow, and stack overflow through pcall
	function stackinfinite() return stackinfinite() end
	checkerror(pcall(stackinfinite))

	function stackover() return pcall(stackover) end
	local res = {pcall(stackover)}
	assert(#res == 200) -- stack limit (MAXCCALLS) is 200
end

-- yield tests
checkresults({ "yield", "return", true, 42 }, colog(function() return pcall(function() coroutine.yield() return 42 end) end))
checkresults({ "yield", 1, "return", true, 42 }, colog(function() return pcall(function() coroutine.yield(1) return 42 end) end))
checkresults({ "yield", 1, 2, 3, "return", true, 42 }, colog(function() return pcall(function() coroutine.yield(1, 2, 3) return 42 end) end))
checkresults({ "yield", 1, "yield", 2, "yield", 3, "return", true, 42 }, colog(function() return pcall(function() for i=1,3 do coroutine.yield(i) end return 42 end) end))
checkresults({ "yield", "return", true, 1, 2, 3}, colog(function() return pcall(function() coroutine.yield() return 1, 2, 3 end) end))

-- recursive yield tests
checkresults({ "yield", 1, "yield", 2, "return", true, true, 3}, colog(function() return pcall(function() coroutine.yield(1) return pcall(function() coroutine.yield(2) return 3 end) end) end))

-- error after yield tests
checkresults({ "yield", "return", false, "pcall.lua:80: foo" }, colog(function() return pcall(function() coroutine.yield() error("foo") end) end))
checkresults({ "yield", "yield", "return", true, false, "pcall.lua:81: foo" }, colog(function() return pcall(function() coroutine.yield() return pcall(function() coroutine.yield() error("foo") end) end) end))
checkresults({ "yield", "yield", "return", false, "pcall.lua:82: bar" }, colog(function() return pcall(function() coroutine.yield() pcall(function() coroutine.yield() error("foo") end) error("bar") end) end))

-- returning lots of results (past MINSTACK limits)
local res = {pcall(function() return table.unpack(table.create(100, 'a')) end)}
assert(#res == 101 and res[1] == true and res[2] == 'a' and res[101] == 'a')

local res = {corun(function() return pcall(function() coroutine.yield() return table.unpack(table.create(100, 'a')) end) end)}
assert(#res == 102 and res[1] == true and res[2] == true and res[3] == 'a' and res[102] == 'a')

-- pcall a C function after yield; resume gets multiple C entries this way
checkresults({ "yield", 1, 2, 3, "return", true }, colog(function() return pcall(coroutine.yield, 1, 2, 3) end))
checkresults({ "yield", 1, 2, 3, "return", true, true, true }, colog(function() return pcall(pcall, pcall, coroutine.yield, 1, 2, 3) end))
checkresults({ "yield", "return", true, true, true, 42 }, colog(function() return pcall(pcall, pcall, function() coroutine.yield() return 42 end) end))

-- xpcall basic tests, including yielding; xpcall uses the same infra as pcall so the main testing opportunity is for error handling
checkresults({ true, 42 }, xpcall(function() return 42 end, error))
checkresults({ true, 1, 2, 42 }, xpcall(function(a, b) return a, b, 42 end, error, 1, 2))
checkresults({ true, 2 }, xpcall(function(...) return select('#', ...) end, error, 1, 2))
checkresults({ "yield", "return", true, 42 }, colog(function() return xpcall(function() coroutine.yield() return 42 end, error) end))

-- xpcall immediate error handling
checkresults({ false, "pcall.lua:103: foo" }, xpcall(function() error("foo") end, function(err) return err end))
checkresults({ false, "bar" }, xpcall(function() error("foo") end, function(err) return "bar" end))
checkresults({ false, 1 }, xpcall(function() error("foo") end, function(err) return 1, 2 end))
checkresults({ false, "pcall.lua:106: foo\npcall.lua:106\npcall.lua:106\n" }, xpcall(function() error("foo") end, debug.traceback))
checkresults({ false, "error in error handling" }, xpcall(function() error("foo") end, function(err) error("bar") end))

-- xpcall error handling after yields
checkresults({ "yield", "return", false, "pcall.lua:110: foo" }, colog(function() return xpcall(function() coroutine.yield() error("foo") end, function(err) return err end) end))
checkresults({ "yield", "return", false, "pcall.lua:111: foo\npcall.lua:111\npcall.lua:111\n" }, colog(function() return xpcall(function() coroutine.yield() error("foo") end, debug.traceback) end))

-- xpcall error handling during error handling inside xpcall after yields
checkresults({ "yield", "return", true, false, "error in error handling" }, colog(function() return xpcall(function() return xpcall(function() coroutine.yield() error("foo") end, function(err) error("bar") end) end, error) end))

-- xpcall + pcall + yield
checkresults({"yield", 42, "return", true, true, true}, colog(function() return xpcall(pcall, function (...) return ... end, function() return pcall(function() coroutine.yield(42) end) end) end))

-- xpcall error
checkresults({ false, "missing argument #2 to 'xpcall' (function expected)" }, pcall(xpcall, function() return 42 end))
checkresults({ false, "invalid argument #2 to 'xpcall' (function expected, got boolean)" }, pcall(xpcall, function() return 42 end, true))

-- stack overflow during coroutine resumption
function weird()
coroutine.yield(weird)
weird()
end

checkresults({ false, "pcall.lua:129: cannot resume dead coroutine" }, pcall(function() for _ in coroutine.wrap(pcall), weird do end end))

-- c++ exception
checkresults({ false, "oops" }, pcall(cxxthrow))

-- resumeerror
local co = coroutine.create(function()
	local ok, err = pcall(function()
		coroutine.yield()
	end)
	coroutine.yield()
	return ok, err
end)

coroutine.resume(co)
resumeerror(co, "fail")
checkresults({ true, false, "fail" }, coroutine.resume(co))

-- stack overflow needs to happen at the call limit
local calllimit = 20000
function recurse(n) return n <= 1 and 1 or recurse(n-1) + 1 end

-- we use one frame for top-level function and one frame is the service frame for coroutines
assert(recurse(calllimit - 2) == calllimit - 2)

-- note that when calling through pcall, pcall eats one more frame
checkresults({ true, calllimit - 3 }, pcall(recurse, calllimit - 3))
checkerror(pcall(recurse, calllimit - 2))

-- xpcall handler runs in context of the stack frame, but this works just fine since we allow extra stack consumption past stack overflow
checkresults({ false, "ok" }, xpcall(recurse, function() return string.reverse("ko") end, calllimit - 2))

-- however, if xpcall handler itself runs out of extra stack space, we get "error in error handling"
checkresults({ false, "error in error handling" }, xpcall(recurse, function() return recurse(calllimit) end, calllimit - 2))

-- simulate OOM and make sure we can catch it with pcall or xpcall
checkresults({ false, "not enough memory" }, pcall(function() table.create(1e6) end))
checkresults({ false, "not enough memory" }, xpcall(function() table.create(1e6) end, function(e) return e end))
checkresults({ false, "oops" }, xpcall(function() table.create(1e6) end, function(e) return "oops" end))
checkresults({ false, "error in error handling" }, xpcall(function() error("oops") end, function(e) table.create(1e6) end))
checkresults({ false, "not enough memory" }, xpcall(function() table.create(1e6) end, function(e) table.create(1e6) end))

co = coroutine.create(function() table.create(1e6) end)
coroutine.resume(co)
checkresults({ false, "not enough memory" }, coroutine.close(co))

-- ensure that pcall and xpcall close upvalues when handling error
local upclo
local function uptest(y)
	local a, b, c, d = 1, 2, 3, 4
	upclo = function()
		local t = table.pack("a", "b", "d", "e", "f", "g", "h", "i")
		assert(a == 1)
		assert(b == 2)
		assert(c == 3)
		assert(d == 4)
		a, b, c, d = table.unpack(t)
		return "ok"
	end
	if y then
		y()
	end
	error("oops")
end

-- ensure that pcall and xpcall close upvalues when handling error (immediate)
do
	upclo = nil
	pcall(uptest, nil)
	assert(upclo() == "ok")
end

do
	upclo = nil
	xpcall(uptest, function(err) end, nil)
	assert(upclo() == "ok")
end

do
	upclo = nil
	xpcall(uptest, function(err) return "e", "e", "e", "e", "e", "e", "e", "e" end, nil)
	assert(upclo() == "ok")
end

-- ensure that pcall and xpcall close upvalues when handling error (deferred)
do
	upclo = nil
	checkresults({"yield", "return", "ok"}, colog(function()
		pcall(uptest, coroutine.yield)
		return upclo()
	end))
end

do
	upclo = nil
	checkresults({"yield", "return", "ok"}, colog(function()
		xpcall(uptest, function(err) end, coroutine.yield)
		return upclo()
	end))
end

do
	upclo = nil
	checkresults({"yield", "return", "ok"}, colog(function()
		xpcall(uptest, function(err) return "e", "e", "e", "e", "e", "e", "e", "e" end, coroutine.yield)
		return upclo()
	end))
end

-- also cover an edge case where xpcall's error handler may want access to the upvalues (immediate + deferred)
do
	local ur
	upclo = nil
	xpcall(uptest, function(err)
		ur = upclo()
	end, nil)
	assert(ur == "ok")
end

do
	local ur
	upclo = nil
	checkresults({"yield", "return"}, colog(function()
		xpcall(uptest, function(err)
			ur = upclo()
		end, coroutine.yield)
	end))
	assert(ur == "ok")
end

-- test stack overflow from a thread that had an error, recovered, and subsequently called coroutine.resume again
if not limitedstack then
	local count = 0
	local function foo()
		count += 1
		pcall(1)   -- create an error
		coroutine.wrap(foo)()   -- call another coroutine
	end
	checkerror(pcall(foo)) -- triggers C stack overflow
	assert(count + 1 == 200) -- stack limit (MAXCCALLS) is 200, -1 for first pcall
end

return 'OK'
