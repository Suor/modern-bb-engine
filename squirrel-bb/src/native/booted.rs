//! The natives as the engine installed them, for its own calls between natives: the
//! original's natives call each other inside the exe, so a script's replacement of a root
//! function isn't what a native calls (probe `campaign/root_calls`).

use squirrel::{SQVM, SqStrongRef, SqTable};

const KEY: &str = "bb_booted_natives";
const TABLES: &[&str] = &["Time", "World", "Tactical", "IO", "Settings"];
const FUNCTIONS: &[&str] = &["createVec", "createColor", "logError", "logWarning", "isKindOf"];

/// Keep the natives as they are now. Call once every native is installed, before any script runs.
pub(crate) fn keep(vm: &SQVM) {
	let root = SqTable::root(vm);
	let mut kept = SqTable::new(vm);
	for &name in TABLES {
		if let Some(t) = root.get::<SqTable>(name) {
			kept.set(name, t.shallow_clone());
			// Bound to the copy: an overload's dispatcher finds its overloads on `this`.
			if let (Some(mut copy), Some(env)) = (kept.get::<SqTable>(name), kept.get::<SqTable>(name)) {
				copy.bind_closures_to(&env);
			}
		}
	}
	for &name in FUNCTIONS {
		if let Some(f) = root.get::<SqStrongRef>(name) {
			kept.set(name, f);
		}
	}
	SqTable::registry(vm).set(KEY, kept);
}

/// The native at `path` (`"Time.getDelta"`, `"createVec"`) as kept; the root's while nothing is.
pub(crate) fn native(vm: &SQVM, path: &str) -> Option<SqStrongRef> {
	let base = SqTable::registry(vm).get::<SqTable>(KEY).unwrap_or_else(|| SqTable::root(vm));
	match path.split_once('.') {
		Some((table, name)) => base.get::<SqTable>(table)?.get::<SqStrongRef>(name),
		None => base.get::<SqStrongRef>(path),
	}
}
