//! The BB `toHash(obj)` root global, as the original's (see [`squirrel::ScriptHash`]):
//! a string's content hash, an integer's or bool's value, a float truncated, and the
//! object's serial for everything else (the original's address, shifted). `item.getInstanceID()` uses
//! `toHash(this).tostring()` to key an item by identity; Reforged seeds its "fixed"
//! rolls with the hash of a string, which must be the same in every run.

use squirrel::{SQVM, ScriptHash};

/// Register the `toHash` root global.
pub(crate) fn install(vm: &mut SQVM) {
	vm.register("toHash", |x: ScriptHash| x.0);
}
