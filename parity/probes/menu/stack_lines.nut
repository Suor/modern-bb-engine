// mode: menu
// The line a stack frame reports while it calls: the line after the call when the call ends
// one and the next line starts at the instruction after it, as the original's (3.0) search
// of the line table finds it. In a game script (event.setScreen calling the screen's
// start) and in a probe's own function.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local seen = [];
// Lines in this file count from here: where it sits in its group's script varies.
local first = ::getstackinfos(1).line;
local function look( ... )
{
	local s = ::getstackinfos(2);
	seen.push(s.func + " " + s.src + ":" + (s.src == "parity" ? "+" + (s.line - first) : "" + s.line));
}
local e = ::new("scripts/events/event");
try { e.setScreen({ ID = "A", Text = "", Options = [], start = look }); } catch (x) {}
p("event.setScreen calling start", @() seen.len() == 0 ? "not called" : seen[0]);
local function caller( _cb )
{
	_cb();
	local x = 1;
	_cb(); local y = 2;
	_cb(
	);
	return x + y;
}
seen.clear();
caller(look);
foreach (i, s in seen) p("a probe's function, call " + i, @() s);
