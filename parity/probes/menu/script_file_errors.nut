// mode: menu
// A script file that is missing: the failure is logged, every time, and the caller goes on (its try never sees it).
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
::logInfo("PROBE_LOG include missing");
p("include missing", @() caught(@() ::include("scripts/bb_probe/missing_file")));
::logInfo("PROBE_LOG include missing again");
p("include missing again", @() caught(@() ::include("scripts/bb_probe/missing_file")));
