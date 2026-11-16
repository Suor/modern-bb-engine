// mode: campaign seed=saveloadcalls
// Which root-table functions the settings' and the campaign's save and load call through a
// script's replacement, as `root_calls` does for the rest. Around the settings' natives
// every call of a wrapper counts; around the campaign's save and load, whose scripts call
// the wrapped functions themselves, only a call from a native frame or from no frame.
// A group of its own: it loads a campaign, so it runs last.

local R = {
	Window = null,
	NativeOnly = false,
	Hits = {},
	Wrapped = [
		"Settings.getGameplaySettings", "Settings.getTempGameplaySettings", "Settings.getControlSettings",
		"Settings.getVideoMode", "Settings.isHardwareSound", "Settings.getSoundVolume", "Settings.setHardwareSound",
		"Settings.setSoundVolume", "IO.scriptFilenameByHash", "IO.scriptHashByFilename", "Time.getVirtualTimeF",
		"Time.getRealTime", "World.getTile", "World.getTileSquare", "World.worldToTile", "World.getMapSize",
		"World.isVisible", "createVec", "createColor", "logError", "logWarning", "isKindOf"
	]
};
local function hits()
{
	local keys = [];
	foreach (k, _ in R.Hits) keys.push(k);
	keys.sort();
	R.Hits = {};
	return keys.len() == 0 ? "none" : keys.reduce(@(a, b) a + ", " + b);
}
local function wrap( _path )
{
	local parts = split(_path, "."), owner = parts.len() == 2 ? ::getroottable()[parts[0]] : ::getroottable();
	local name = parts.top(), orig = owner[name];
	owner[name] = function( ... )
	{
		if (R.Window != null)
		{
			if (!R.NativeOnly) R.Hits[_path] <- true;
			else
			{
				local who = ::getstackinfos(2);
				if (who == null) R.Hits[_path + " from nothing"] <- true;
				else if (who.src == "NATIVE") R.Hits[_path + " from native " + who.func] <- true;
			}
		}
		local args = [this];
		args.extend(vargv);
		return orig.acall(args);
	};
}
local function around( _k, _nativeOnly, _f )
{
	local v;
	R.Hits = {};
	R.Window = _k;
	R.NativeOnly = _nativeOnly;
	try { _f(); v = "ok"; } catch (e) { v = "ERROR " + e; }
	R.Window = null;
	::logInfo("PROBE " + _k + " = string " + v + ", calls " + hits());
}

foreach (path in R.Wrapped) wrap(path);
local mode = ::Settings.getVideoMode();
around("Settings.save", false, @() ::Settings.save());
around("Settings.saveWithCustomVideoMode", false, @() ::Settings.saveWithCustomVideoMode(mode));
around("Settings.load video only", false, @() ::Settings.load(true));
around("Settings.load", false, @() ::Settings.load(false));
around("saveCampaign", true, @() ::World.State.saveCampaign("bb_probe_save_load_calls"));
around("loadCampaign", true, @() ::World.State.loadCampaign("bb_probe_save_load_calls"));
