//! Script-path hashing (`ClassNameHash`) and small path helpers.
//!
//! Battle Brothers refers to every script by an extension-less, forward-slash
//! path (e.g. `scripts/skills/skill`). The engine stamps a stable integer hash of
//! that path — `ClassNameHash` — onto every object the module system builds, and
//! exposes a bidirectional path↔hash registry through `IO`.
//!
//! The hash is the original's (disassembled at `0x5474c2`): `h = h * 37 + byte` over
//! the path without its extension, the bytes taken as signed chars, in wrapping 32-bit
//! arithmetic. Original saves store these values (`ClassNameHash` of items and skills,
//! `IO.scriptHashByFilename` of troop scripts), so importing them depends on it. The
//! same function stamps objects and answers `IO` queries.

/// A script's name, as the original takes it (parity probe `menu/script_paths`): the path
/// cut at its last `.`, kept otherwise as written (spaces, case, backslashes). It keys
/// the run-once guard and the class cache and is hashed, so a file runs again under
/// another spelling that [`lookup_path`] finds.
pub fn normalize_path(path: &str) -> String {
	path.rfind('.').map_or(path, |dot| &path[..dot]).to_string()
}

/// Where the original looks a script named `norm` up: repeated and leading slashes collapsed.
pub(crate) fn lookup_path(norm: &str) -> String {
	norm.split('/').filter(|s| !s.is_empty()).collect::<Vec<_>>().join("/")
}

/// The final path segment — the BB "class name": `scripts/skills/actives/bash`
/// → `bash`. Used for the super-reference slot and for [`isKindOf`] matching.
///
/// [`isKindOf`]: crate::ModuleSystem
pub fn basename(path: &str) -> &str {
	let path = path.strip_suffix(".nut").unwrap_or(path);
	match path.rfind('/') {
		Some(slash) => &path[slash + 1..],
		None => path,
	}
}

/// The original's hash of the normalized path, as the `i32` it is, widened to the `i64`
/// that Squirrel integers use. Stamps `ClassNameHash` and populates the `IO` registry.
pub fn class_name_hash(path: &str) -> i64 {
	let hash = normalize_path(path)
		.bytes()
		.fold(0i32, |h, b| h.wrapping_mul(37).wrapping_add(i32::from(b as i8)));
	i64::from(hash)
}

#[cfg(test)]
mod tests {
	use super::{basename, class_name_hash, normalize_path};

	#[test]
	fn normalizes_path_variants_to_one_form() {
		assert_eq!(
			normalize_path("scripts/skills/skill"),
			"scripts/skills/skill"
		);
		assert_eq!(
			normalize_path("scripts/skills/skill.nut"),
			"scripts/skills/skill"
		);
		assert_eq!(normalize_path("scripts/skills/skill.cnut"), "scripts/skills/skill");
		assert_eq!(normalize_path("scripts/skills/../skills/skill"), "scripts/skills/.");
		assert_eq!(normalize_path("scripts\\skills\\skill"), "scripts\\skills\\skill");
		assert_eq!(
			normalize_path("scripts/skills/skill .nut"),
			"scripts/skills/skill "
		);
	}

	#[test]
	fn basename_is_the_last_segment() {
		assert_eq!(basename("scripts/skills/actives/bash"), "bash");
		assert_eq!(basename("scripts/skills/actives/bash.nut"), "bash");
		assert_eq!(basename("skill"), "skill");
	}

	#[test]
	fn hash_is_stable_and_path_invariant() {
		// A path hashes the same with or without its extension.
		let h = class_name_hash("scripts/skills/skill");
		assert_eq!(h, class_name_hash("scripts/skills/skill.nut"));
		// Distinct paths hash differently.
		assert_ne!(h, class_name_hash("scripts/skills/actives/bash"));
		// Values the original gives (a probe, and the hashes in its save files).
		assert_eq!(h, -315995513);
		assert_eq!(class_name_hash("scripts/entity/tactical/player"), 0xe9a7_c4d4_u32 as i32 as i64);
	}
}
