// mode: campaign seed=navhookerrors
// Errors in what the navigator calls, in a battle against bandits once the first turn has
// started (one starting while units fly crashes the original), the AI paused from the
// start. A unit's movement hooks are the class's, so an error is raised in them by a
// property read: the unit's `m.CurrentProperties` throws when read by the named functions.
// Reported: what the native answers, where the units end, which functions raised and how
// often. A group of its own: it fights, and waits for the moves (`BbProbe.DeferDone`).

::BbProbe.DeferDone = true;
::__navErr <- {
	Waited = 0,
	Raised = [],
	Calls = 0,
	function log( _k, _v ) { ::logInfo("PROBE " + _k + " = " + typeof _v + " " + (_v == null ? "null" : _v)); },
	function later( _ms, _f ) { ::Time.scheduleEvent(::TimeUnit.Real, _ms, _f, null); },
	function raised()
	{
		local out = ::__navErr.Raised.len() == 0 ? "none" : ::__navErr.Raised.reduce(@(a, b) a + " " + b);
		::__navErr.Raised = [];
		return out;
	},
	// The unit's properties, throwing when one of `_funcs` reads them.
	function bomb( _e, _funcs )
	{
		local real = _e.m.CurrentProperties;
		_e.m.CurrentProperties = {}.setdelegate({
			_get = function( _f )
			{
				local who = ::getstackinfos(2);
				if (who != null && _funcs.find(who.func) != null)
				{
					::__navErr.Raised.push(who.func);
					throw "BB_PROBE_NAV";
				}
				local v = real[_f];
				return typeof v == "function" ? v.bindenv(real) : v;
			}
			_set = function( _f, _v ) { real[_f] = _v; }
		});
		return real;
	},
	function thrower()
	{
		return function( ... ) { ::__navErr.Calls++; throw "BB_PROBE_NAV"; };
	},
	function answer( _f )
	{
		try { return "" + _f(); } catch( e ) { return "threw " + e; }
	},
	function enemies()
	{
		if (!("Entities" in ::Tactical) || ::Tactical.Entities == null) return [];
		// Not the one whose turn it is.
		local out = [], active = ::Tactical.TurnSequenceBar.getActiveEntity();
		foreach (e in ::Tactical.Entities.getInstancesOfFaction(::Const.Faction.Enemy))
			if (e.isPlacedOnMap() && e.isAlive() && (active == null || active.getID() != e.getID())) out.push(e);
		return out;
	},
	// Empty tiles the player sees, at least `_gap` from every unit and from `_taken`.
	function freeTiles( _gap, _taken )
	{
		local out = [], size = ::Tactical.getMapSize();
		for (local x = 3; x < size.X - 3; x++)
			for (local y = 3; y < size.Y - 3; y++)
			{
				local t = ::Tactical.getTileSquare(x, y);
				if (!t.IsEmpty || !t.IsVisibleForPlayer) continue;
				local ok = true;
				foreach (a in ::Tactical.Entities.getAllInstancesAsArray())
					if (a.isPlacedOnMap() && a.getTile().getDistanceTo(t) < _gap) ok = false;
				foreach (u in _taken)
					if (u.getDistanceTo(t) < _gap) ok = false;
				if (ok) out.push(t);
			}
		return out;
	},
	function place( _e, _t ) { return ::Tactical.getNavigator().teleport(_e, _t, null, null, false, 0.0); },
	function answerIntro( _ )
	{
		local screen = ::World.State.getEventScreen();
		if (screen != null && screen.isVisible()) screen.onButtonPressed(0);
		::__navErr.later(2500, ::__navErr.start);
	},
	function start( _ )
	{
		local st = ::World.State;
		local p = st.getLocalCombatProperties(st.getPlayer().getPos());
		p.CombatID = "Event";
		p.IsAutoAssigningBases = false;
		p.Entities = [];
		::Const.World.Common.addUnitsToCombat(p.Entities, ::Const.World.Spawn.BanditDefenders, 100, ::Const.Faction.Enemy);
		st.startScriptedCombat(p, false, false, true);
		::__navErr.later(50, ::__navErr.wait);
	},
	function wait( _ )
	{
		// The AI paused as soon as the battle is there, before it moves anyone: the navigator
		// refuses moves while one of its moves is under way.
		local up = ("State" in ::Tactical) && ::Tactical.State != null;
		if (up) ::Tactical.State.m.IsAIPaused = true;
		up = up && ::__navErr.enemies().len() >= 3 && ::Tactical.TurnSequenceBar.getActiveEntity() != null;
		if (!up && ++::__navErr.Waited < 1200)
		{
			::__navErr.later(50, ::__navErr.wait);
			return;
		}
		if (!up)
		{
			::__navErr.log("battle", "ERROR the battle never began");
			::BbProbe.done();
			return;
		}
		::__navErr.Waited = 0;
		::__navErr.later(1000, ::__navErr.teleports);
	},
	function teleports( _ )
	{
		local P = ::__navErr, nav = ::Tactical.getNavigator(), e = P.enemies();
		local t = P.freeTiles(4, []);
		local a = t[0], b = P.freeTiles(4, [a])[0];
		if (!(P.place(e[0], a) && P.place(e[1], b)) && ++P.Waited < 480)
		{
			P.later(500, P.teleports);
			return;
		}
		P.log("placed", e[0].getTile().ID == a.ID && e[1].getTile().ID == b.ID);
		local to = P.freeTiles(3, [])[0];
		P.Calls = 0;
		P.log("teleport, onDone raises", P.answer(@() nav.teleport(e[0], to, P.thrower(), "tag", false, 0.0)));
		P.log("teleport, onDone raises: moved", e[0].getTile().ID == to.ID);
		P.log("teleport, onDone raises: calls", P.Calls);
		to = P.freeTiles(3, [])[0];
		local real = P.bomb(e[0], ["onMovementFinish"]);
		P.log("teleport, onMovementFinish raises", P.answer(@() nav.teleport(e[0], to, null, "tag", false, 0.0)));
		e[0].m.CurrentProperties = real;
		P.log("teleport, onMovementFinish raises: moved", e[0].getTile().ID == to.ID);
		P.log("teleport, onMovementFinish raises: raised", P.raised());
		P.A <- e[0].getTile(); P.B <- e[1].getTile();
		P.Calls = 0;
		P.log("switchEntities, onDone raises", P.answer(@() nav.switchEntities(e[0], e[1], P.thrower(), "tag", 1.0)));
		P.later(3000, P.switched);
	},
	function switched( _ )
	{
		local P = ::__navErr, e = P.enemies();
		P.log("switchEntities, onDone raises: swapped", e[0].getTile().ID == P.B.ID && e[1].getTile().ID == P.A.ID);
		P.log("switchEntities, onDone raises: calls", P.Calls);
		P.travel(e[0], ["onMovementStep"], "travel, onMovementStep raises", null);
	},
	// `_e` travels 2 tiles from a free tile; `_neighbour`, if given, stands next to its start.
	function travel( _e, _funcs, _k, _neighbour )
	{
		local P = ::__navErr, nav = ::Tactical.getNavigator();
		local start = P.freeTiles(4, [])[0];
		P.place(_e, start);
		if (_neighbour != null)
		{
			for (local i = 0; i < 6; i++)
				if (start.hasNextTile(i) && start.getNextTile(i).IsEmpty && P.place(_neighbour, start.getNextTile(i))) break;
		}
		local dest = null;
		foreach (t in P.freeTiles(1, [])) if (t.getDistanceTo(start) == 2 && (_neighbour == null || t.getDistanceTo(_neighbour.getTile()) >= 3)) { dest = t; break; }
		_e.m.ActionPoints = 9;
		local settings = nav.createSettings();
		settings.ActionPointCosts = ::Const.DefaultMovementAPCost;
		settings.FatigueCosts = ::Const.DefaultMovementFatigueCost;
		settings.AllowZoneOfControlPassing = true;
		P.log(_k + ": path", nav.findPath(start, dest, settings, 0));
		P.Travel <- {e = _e, k = _k, start = start, dest = dest, real = P.bomb(_e, _funcs), first = null, n = 0};
		P.later(50, P.travelling);
	},
	function travelling( _ )
	{
		local P = ::__navErr, T = P.Travel, nav = ::Tactical.getNavigator();
		local r = P.answer(@() nav.travel(T.e, 9, 99));
		if (T.first == null) T.first = r;
		if (r == "true" && ++T.n < 200)
		{
			P.later(50, P.travelling);
			return;
		}
		T.e.m.CurrentProperties = T.real;
		P.log(T.k, T.first + ".." + r);
		local at = T.e.getTile();
		P.log(T.k + ": at", at.ID == T.dest.ID ? "dest" : at.ID == T.start.ID ? "start" : "a tile " + at.getDistanceTo(T.start) + " from the start");
		P.log(T.k + ": AP", T.e.m.ActionPoints);
		P.log(T.k + ": raised", P.raised());
		if (T.k == "travel, onMovementStep raises")
		{
			local e = P.enemies();
			P.travel(e[0], ["onMovementStep", "onMovementInZoneOfControl", "onAttackOfOpportunity"], "travel next to a unit, its hooks raise", e[1]);
			return;
		}
		::BbProbe.done();
	}
};
::__navErr.later(2500, ::__navErr.answerIntro);
