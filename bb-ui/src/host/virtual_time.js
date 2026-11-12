// Injected into a headless page (HostConfig::headless), after page_work.js.
//
// The page's clock follows the game's frames instead of the wall clock: a headless run
// steps frames as fast as it can, so timers and animations on real time would run
// slower than the game by however fast that is, and differently run to run. Until the
// host first calls `__bbClock(gameMs)` everything runs on the wall clock (the page
// loads, the menu boots). From then on `performance.now()`, `Date`, timers and
// animation frames run only in `__bbClock` calls, each advancing the clock to the
// game's time: the timers due by then run in due order (one set meanwhile waits for
// the next call, as Coherent ran a frame's timers), then the animation frames asked
// for before the call, with the call's time. CSS animations and transitions stay on
// Chromium's clock. `__bbClock` returns `[next, pictures]`: the game time of the next
// timer (the call's own if animation frames wait, -1 if none), and how many pictures
// the page asked for haven't loaded yet (`__bbPictures()` too): their loads take real
// time, so a host that waits for them keeps the frame they land in the same run to run.
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
	// `new Date()` too: Velocity times its animations by it.
	var NativeDate = Date;
	function dateNow() {
		return virtual ? Math.round(clock() + dateOffset) : nativeDateNow();
	}
	function VirtualDate() {
		if (!(this instanceof VirtualDate)) {
			return new NativeDate(dateNow()).toString();
		}
		if (arguments.length === 0) {
			return new NativeDate(dateNow());
		}
		return new (Function.prototype.bind.apply(NativeDate, [null].concat(slice.call(arguments))))();
	}
	VirtualDate.prototype = NativeDate.prototype;
	VirtualDate.now = dateNow;
	VirtualDate.parse = NativeDate.parse;
	VirtualDate.UTC = NativeDate.UTC;
	window.Date = VirtualDate;

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

	// Pictures asked for (`src` set) whose load or error event hasn't run; one complete
	// for 100 ms of real time without its event is let go (one may fire none).
	var pictures = new Map();
	function settled(e) {
		pictures.delete(e.target);
	}
	function asked(image) {
		pictures.set(image, null);
		image.addEventListener('load', settled);
		image.addEventListener('error', settled);
	}
	var src = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
	Object.defineProperty(HTMLImageElement.prototype, 'src', {
		configurable: true,
		enumerable: src.enumerable,
		get: src.get,
		set: function (value) {
			src.set.call(this, value);
			asked(this);
		}
	});
	var setAttribute = Element.prototype.setAttribute;
	Element.prototype.setAttribute = function (name, value) {
		setAttribute.call(this, name, value);
		if (this instanceof HTMLImageElement && String(name).toLowerCase() === 'src') {
			asked(this);
		}
	};
	function loadingPictures() {
		var wall = nativePerformanceNow();
		pictures.forEach(function (completeSince, image) {
			if (!image.complete) {
				return;
			}
			if (completeSince === null) {
				pictures.set(image, wall);
			} else if (wall - completeSince > 100) {
				pictures.delete(image);
			}
		});
		return pictures.size;
	}
	Object.defineProperty(window, '__bbPictures', { value: loadingPictures, enumerable: false });

	// For diagnostics: what waits on the clock.
	Object.defineProperty(window, '__bbClockState', {
		value: function () {
			return { virtual: virtual, now: now, timers: timers.size, frames: frames.size, next: nextDue() };
		},
		enumerable: false
	});

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
			var next = nextDue();
			next = frames.size > 0 ? gameMs : next === Infinity ? -1 : gameBase + (next - base);
			return [next, loadingPictures()];
		},
		enumerable: false
	});
})();
