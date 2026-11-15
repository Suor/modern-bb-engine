// mode: menu
// How include(), new() and IO name a script: the path is cut at its last `.`, kept otherwise as written (spaces,
// case, backslashes); the file is looked up with repeated and leading slashes collapsed, but a loaded file runs
// again under another spelling. Runs are counted by sleeping_effect's top-level inherit().
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local real = ::inherit;
local calls = 0;
::inherit = function( _src, _proto ) { calls++; return real(_src, _proto); };
local file = "scripts/skills/effects/sleeping_effect";
foreach (s in [file, file + ".nut", file + ".cnut", file + ".x", file + " ", " " + file, file + " .nut",
	"Scripts/skills/effects/sleeping_effect", "scripts\\skills\\effects\\sleeping_effect", "./" + file,
	"scripts/skills/effects/../effects/sleeping_effect", "scripts//skills/effects/sleeping_effect",
	"again scripts//skills/effects/sleeping_effect", "/" + file, "scripts/skills//effects/sleeping_effect.nut"])
{
	calls = 0;
	::logInfo("PROBE_LOG include '" + s + "'");
	local r;
	try { ::include(::String.replace(s, "again ", "")); r = "runs=" + calls; } catch (e) { r = "ERROR " + e; }
	::logInfo("PROBE include '" + s + "' = string " + r);
}
::inherit = real;
foreach (s in [file, file + ".nut", file + " ", "scripts//skills/effects/sleeping_effect", "/" + file])
{
	::logInfo("PROBE_LOG new '" + s + "'");
	p("new '" + s + "'", function() {
		local r = ::new(s);
		return r == null ? "null" : r.m.ID + " " + r.ClassName + " " + r.ClassNameHash;
	});
}
foreach (s in [file, file + " ", file + ".nut", "scripts//skills/effects/sleeping_effect", "/" + file, "scripts/nope"])
	p("hash '" + s + "'", @() ::IO.scriptHashByFilename(s));
