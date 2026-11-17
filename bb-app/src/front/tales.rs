//! bbtales's page natives in the windowed game (`bbtales.py --env ui --show`), as its headless
//! `bbtales_ui` has them, when `BB_TALES_SHOTS=<dir>` is set: `::BBTales_js(code)` (the page's
//! value of `code` as `{v = value}`; a JS exception raises) and `::BBTales_shot(name)` (a PNG of
//! the window's last frame drawn, the page over the map, `<dir>/<name>.png`).

use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use bb_render::Gpu;
use bb_ui::host::UiSession;
use bb_ui::json::Json;
use squirrel::{SQVM, SqArray, SqRef, SqStrongRef, SqTable};

/// The texture of the last frame drawn (see `Front::draw`).
pub type LastFrame = Rc<RefCell<Option<wgpu::Texture>>>;

pub fn register(session: &mut Box<UiSession>, gpu: &Gpu, frame: LastFrame) {
	let Some(shots) = std::env::var_os("BB_TALES_SHOTS").map(PathBuf::from) else { return };
	let at: *const UiSession = &**session;
	// SAFETY: the session is boxed and owns the VM: the natives can't outlive it, and run on
	// this thread, inside its scripts.
	let session_ref = move || unsafe { &*at };
	let vm = session.engine_mut().vm_mut();
	vm.register("BBTales_js", move |vm: &SQVM, code: String| -> Result<SqStrongRef, String> {
		let value = session_ref().eval(&code)?;
		let mut result = SqTable::new(vm);
		result.set("v", to_sq(vm, &value));
		Ok(result.to_strong())
	});
	let (device, queue) = (gpu.device.clone(), gpu.queue.clone());
	vm.register("BBTales_shot", move |name: String| -> Result<String, String> {
		let texture = frame.borrow().clone().ok_or("no frame drawn yet")?;
		let image = bb_render::read_level_on(&device, &queue, &texture, 0)?;
		let path = shots.join(format!("{name}.png"));
		bb_render::save_png(&path, &image).map_err(|e| format!("{}: {e}", path.display()))?;
		Ok(path.to_string_lossy().into_owned())
	});
}

/// A JS value as Squirrel's: numbers keep their fractions (unlike the bridge's `from_json`).
fn to_sq<'vm>(vm: &'vm SQVM, json: &Json) -> SqRef<'vm> {
	match json {
		Json::Null => SqRef::Null,
		Json::Bool(b) => SqRef::Bool(*b),
		Json::Int(n) => SqRef::Integer(*n),
		Json::Float(f) if f.fract() == 0.0 && f.abs() < 9e15 => SqRef::Integer(*f as i64),
		Json::Float(f) => SqRef::Float(*f),
		Json::Str(s) => SqRef::String(s.clone()),
		Json::Array(items) => {
			let mut array = SqArray::new(vm);
			for item in items {
				array.push(to_sq(vm, item));
			}
			SqRef::Array(array)
		}
		Json::Object(entries) => {
			let mut table = SqTable::new(vm);
			for (key, value) in entries {
				table.set(key.as_str(), to_sq(vm, value));
			}
			SqRef::Table(table)
		}
	}
}
