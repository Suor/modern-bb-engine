// mode: menu
// What the compiler makes of text source (a mod's `.nut`): the original's is Squirrel 3.0.4,
// where `in` and `instanceof` bind as loosely as `&&`.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local tb = { a = 1 };
p("\"a\" in tb == false", @() "a" in tb == false);
p("\"b\" in tb == false", @() "b" in tb == false);
p("\"a\" in tb && false", @() "a" in tb && false);
p("!(\"b\" in tb) == true", @() !("b" in tb) == true);
local C = class {};
local c = C();
p("c instanceof C == false", @() c instanceof C == false);
p("switch on a local", function() {
	local x = 2, r = "none";
	switch (x) { case 1: r = "one"; break; case 2: r = "two"; break; default: r = "default"; }
	return r + ", x after: " + x;
});
p("y += 1 || 0", function() { local y = 0; y += 1 || 0; return y; });

