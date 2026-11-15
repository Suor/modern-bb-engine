// mode: menu
// new() of a class whose create() throws: the error is reported and new() gives the instance as create() left
// it, past the caller's try. Emptying ::Const.SkillType for the call makes sleeping_effect's create() throw
// after it set ID and Overlay, before Type.
local function p( _k, _f )
{
	local v;
	try { v = _f(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE " + _k + " = " + typeof v + " " + (v == null ? "null" : v));
}
local saved = ::Const.SkillType;
::Const.SkillType = {};
local r = "unset", caught = "none";
try { r = ::new("scripts/skills/effects/sleeping_effect"); } catch (e) { caught = e; }
::Const.SkillType = saved;
p("caught", @() caught);
p("type", @() typeof r);
p("ID", @() r.m.ID);
p("Overlay", @() r.m.Overlay);
p("Type", @() r.m.Type);
p("IsRemovedAfterBattle", @() r.m.IsRemovedAfterBattle);
p("ping", @() r.getID());
