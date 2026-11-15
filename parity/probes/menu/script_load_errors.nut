// mode: menu
// Scripts of a mod of the probe's own (`script_load_errors/`). One that doesn't compile is logged
// with the compiler's message and place, once, and the caller goes on. IO.scriptHashByFilename
// knows only scripts under `scripts/` (the sweep ran `inside` at boot), not a mod's elsewhere,
// even once included.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local function caught( _f )
{
	local r = "unset", c = "none";
	try { r = _f(); } catch (e) { c = e; }
	return "caught=" + c + " r=" + typeof r;
}
::logInfo("PROBE_LOG include bad syntax");
p("include bad syntax", @() caught(@() ::include("bb_probe/bad_syntax")));
p("ran", @() "BbProbeBadSyntax" in ::getroottable());
::logInfo("PROBE_LOG include bad syntax again");
p("include bad syntax again", @() caught(@() ::include("bb_probe/bad_syntax")));
p("hash outside", @() ::IO.scriptHashByFilename("bb_probe/outside"));
::logInfo("PROBE_LOG include outside");
p("include outside", @() caught(@() ::include("bb_probe/outside")) + " " + ::BbProbeOutside);
p("hash outside once included", @() ::IO.scriptHashByFilename("bb_probe/outside"));
p("inside ran", @() ::BbProbeInside);
p("hash inside", @() ::IO.scriptHashByFilename("scripts/bb_probe/inside"));
