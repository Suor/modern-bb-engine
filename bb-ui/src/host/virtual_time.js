// Injected first into a headless page (HostConfig::headless), before page_work.js.
//
// The page's clock follows the game's frames instead of the wall clock: a headless run
// steps frames as fast as it can, so timers and animations on real time would run
// slower than the game by however fast that is, and differently run to run. Until the
// host first calls `__bbClock(gameMs)` everything runs on the wall clock (the page
// loads, the menu boots). From then on `performance.now()`, `Date.now()`, timers and
// animation frames run only in `__bbClock` calls, each advancing the clock to the
// game's time: the timers due by then run in due order (one set meanwhile waits for
// the next call, as Coherent ran a frame's timers), then the animation frames asked
// for before the call, with the call's time. CSS animations and transitions stay on
// Chromium's clock. `__bbClock` returns the game time of the next timer, the call's own
// if animation frames wait, or -1.
(function () {
	'use strict';

	var nativeSetTimeout = window.setTimeout;
	var nativeClearTimeout = window.clearTimeout;
	var nativeRequestFrame = window.requestAnimationFrame;
	var nativeCancelFrame = window.cancelAnimationFrame;
	var nativePerformanceNow = performance.now.bind(performance);
	var nativeDateNow = Date.now;
	var slice = Array.prototype.slice;

	var virtual = false;
	// performance.now() at the switch, and the game's time then.
	var base = 0;
	var gameBase = 0;
	var now = 0;
	var dateOffset = 0;

	var nextHandle = 1;
	// handle -> {due, every, run, native}
	var timers = new Map();
	// handle -> {callback, native}
	var frames = new Map();

	// A callback runs as a task of its own: its uncaught error is reported as the
	// browser reports one ("Uncaught …", window.onerror) without stopping the others.
	var runner = new EventTarget();
	var running = null;
	runner.addEventListener('run', function () {
		running();
	});
	function runTask(fn) {
		running = fn;
		runner.dispatchEvent(new Event('run'));
		running = null;
	}

	function delayOf(delay) {
		var ms = Number(delay);
		return ms > 0 ? (ms > 2147483647 ? 1 : ms) : 0;
	}

	function invoke(handler, args) {
		return typeof handler === 'function' ? handler.apply(window, args) : (0, eval)(String(handler));
	}

	function clock() {
		return virtual ? now : nativePerformanceNow();
	}

	function arm(handle, timer) {
		if (!virtual) {
			timer.native = nativeSetTimeout.call(window, function () {
				fire(handle);
			}, Math.max(0, timer.due - nativePerformanceNow()));
		}
	}

	function fire(handle) {
		var timer = timers.get(handle);
		if (!timer) {
			return;
		}
		if (timer.every === null) {
			timers.delete(handle);
		} else {
			timer.due = clock() + timer.every;
			arm(handle, timer);
		}
		timer.run();
	}

	function schedule(handler, delay, args, repeat) {
		var handle = nextHandle++;
		var ms = delayOf(delay);
		var timer = {
			due: clock() + ms,
			every: repeat ? ms : null,
			run: function () { return invoke(handler, args); },
			native: null
		};
		timers.set(handle, timer);
		arm(handle, timer);
		return handle;
	}

	function clear(handle) {
		var timer = timers.get(handle);
		if (timer) {
			if (timer.native !== null) {
				nativeClearTimeout.call(window, timer.native);
			}
			timers.delete(handle);
		}
	}

	window.setTimeout = function setTimeout(handler, delay) {
		return schedule(handler, delay, slice.call(arguments, 2), false);
	};
	window.setInterval = function setInterval(handler, delay) {
		return schedule(handler, delay, slice.call(arguments, 2), true);
	};
	window.clearTimeout = clear;
	window.clearInterval = clear;

	window.requestAnimationFrame = function requestAnimationFrame(callback) {
		var handle = nextHandle++;
		var frame = { callback: callback, native: null };
		if (!virtual) {
			frame.native = nativeRequestFrame.call(window, function (time) {
				frames.delete(handle);
				callback(time);
			});
		}
		frames.set(handle, frame);
		return handle;
	};
	window.cancelAnimationFrame = function cancelAnimationFrame(handle) {
		var frame = frames.get(handle);
		if (frame) {
			if (frame.native !== null) {
				nativeCancelFrame.call(window, frame.native);
			}
			frames.delete(handle);
		}
	};
	if ('webkitRequestAnimationFrame' in window) {
		window.webkitRequestAnimationFrame = window.requestAnimationFrame;
	}
	['webkitCancelAnimationFrame', 'webkitCancelRequestAnimationFrame'].forEach(function (name) {
		if (name in window) {
			window[name] = window.cancelAnimationFrame;
		}
	});

	performance.now = function now() {
		return clock();
	};
	Date.now = function now() {
		return virtual ? Math.round(clock() + dateOffset) : nativeDateNow();
	};

	// From the wall clock to the game's: what was armed natively is taken over.
	function goVirtual(gameMs) {
		base = nativePerformanceNow();
		gameBase = gameMs;
		now = base;
		dateOffset = nativeDateNow() - base;
		virtual = true;
		timers.forEach(function (timer) {
			if (timer.native !== null) {
				nativeClearTimeout.call(window, timer.native);
				timer.native = null;
			}
		});
		frames.forEach(function (frame) {
			if (frame.native !== null) {
				nativeCancelFrame.call(window, frame.native);
				frame.native = null;
			}
		});
	}

	function nextDue() {
		var next = Infinity;
		timers.forEach(function (timer) {
			if (timer.due < next) {
				next = timer.due;
			}
		});
		return next;
	}

	Object.defineProperty(window, '__bbClock', {
		value: function (gameMs) {
			if (!virtual) {
				goVirtual(gameMs);
			}
			var target = Math.max(now, base + (gameMs - gameBase));
			// The timers due by the target and set before this call, earliest first.
			var due = [];
			timers.forEach(function (timer, handle) {
				if (timer.due <= target) {
					due.push({ handle: handle, due: timer.due });
				}
			});
			due.sort(function (a, b) { return a.due - b.due || a.handle - b.handle; });
			due.forEach(function (entry) {
				var timer = timers.get(entry.handle);
				// Cleared or moved by an earlier one.
				if (!timer || timer.due !== entry.due) {
					return;
				}
				now = Math.max(now, timer.due);
				runTask(function () { fire(entry.handle); });
			});
			now = target;
			var asked = [];
			frames.forEach(function (frame, handle) {
				asked.push(handle);
			});
			asked.forEach(function (handle) {
				var frame = frames.get(handle);
				if (frame) {
					frames.delete(handle);
					runTask(function () { frame.callback(target); });
				}
			});
			if (frames.size > 0) {
				return gameMs;
			}
			var next = nextDue();
			return next === Infinity ? -1 : gameBase + (next - base);
		},
		enumerable: false
	});
})();
