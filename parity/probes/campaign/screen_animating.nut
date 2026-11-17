// mode: campaign seed=screenanim
// A screen's show and hide as its script sees them: right after the call, then each state the
// following frames bring, up to the end of its animation.
// A group of its own: it shows a screen and defers.
local screen = ::World.State.m.RelationsScreen;
local function state()
{
	return "animating " + screen.isAnimating() + " visible " + screen.isVisible();
}
local R = {Steps = [["show", @() screen.show(), true], ["hide", @() screen.hide(), false]], Step = 0, Trail = null, Polls = 0};
R.poll <- @() ::Time.scheduleEvent(::TimeUnit.Real, 1, R.check, null);
R.next <- function()
{
	if (R.Step == R.Steps.len()) return ::BbProbe.done();
	local step = R.Steps[R.Step];
	local v;
	try { step[1](); v = state(); } catch (e) { v = "ERROR " + e; }
	::logInfo("PROBE relations " + step[0] + " right after = string " + v);
	R.Trail = [v];
	R.Polls = 0;
	R.poll();
}
R.check <- function( _ )
{
	local step = R.Steps[R.Step], v = state();
	if (v != R.Trail.top()) R.Trail.push(v);
	if ((screen.isAnimating() || screen.isVisible() != step[2]) && ++R.Polls < 600) return R.poll();
	::logInfo("PROBE relations " + step[0] + " then = string " + R.Trail.reduce(@(a, b) a + ", " + b));
	R.Step++;
	R.next();
}
::BbProbe.DeferDone = true;
R.next();
