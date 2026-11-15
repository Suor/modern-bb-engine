// mode: menu
// A script file that is missing or throws at its top level: the failure is logged, the caller goes on (its try
// never sees it), and the file counts as loaded; new() of its class gives null, inherit() from it an empty parent
// without a name. A loaded file runs again under another spelling of its path (`scripts//`), here with inherit()
// made to throw.
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

local path = "scripts//skills/effects/dazed_effect";
local real = ::inherit;
::inherit = function( _src, _proto ) { throw "BB_PROBE_TOP"; };
::logInfo("PROBE_LOG include throws");
local r;
try { r = caught(@() ::include(path)); } catch (e) { r = "ERROR " + e; }
::inherit = real;
p("include throws", @() r);
::logInfo("PROBE_LOG include again");
p("include again", @() caught(@() ::include(path)));
::logInfo("PROBE_LOG new of it");
p("new of it", @() caught(@() ::new(path)));
::logInfo("PROBE_LOG inherit from it");
p("inherit from it", function() {
	local c = ::inherit(path, { m = {} });
	local keys = [];
	foreach (k, v in c) keys.push(k);
	keys.sort();
	return "SuperName='" + c.SuperName + "' super=" + c[c.SuperName].len() + " keys=" + keys.len();
});
p("new by its own path", @() ::new("scripts/skills/effects/dazed_effect").m.ID);
