// mode: menu
// A null made a string, as concatenation does on either side: the original prints it like an
// object at address 0.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
p("string + null", @() "x" + null);
p("null + string", @() null + "x");
p("length", @() ("" + null).len());
p("in a table key", function() { local t = {}; t["" + null] <- 1; foreach (k, v in t) return k; });
p("null.tostring()", @() null.tostring());
