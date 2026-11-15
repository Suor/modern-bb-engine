// mode: menu
// ClassName and ClassNameHash of what inherit() gives: none while its file runs; once it has run, the table under
// the file's name gets them, any other one never. The file runs again under another spelling of its path.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local function cn( _t )
{
	return (_t.rawin("ClassName") ? "'" + _t.ClassName + "'" : "-") + " " + (_t.rawin("ClassNameHash") ? _t.ClassNameHash : "-");
}
local real = ::inherit;
local got = [];
::inherit = function( _src, _proto )
{
	local r = real(_src, _proto);
	got.push([r, cn(r), real(_src, { m = {} })]);
	return r;
};
try { ::include("scripts//skills/effects/staggered_effect"); } catch (e) { ::logInfo("PROBE include = string ERROR " + e); }
::inherit = real;
p("calls", @() got.len());
p("in its file", @() got[0][1]);
p("after", @() cn(got[0][0]));
p("another after", @() cn(got[0][2]));
p("from a function", @() cn(::inherit("scripts/skills/skill", { m = {} })));
p("loaded class", @() cn(::new("scripts/skills/effects/staggered_effect")));
p("hash", @() ::IO.scriptHashByFilename("scripts/skills/effects/staggered_effect"));
