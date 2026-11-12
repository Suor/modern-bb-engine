//! Where the page's paints go: Chromium paints the page on the GPU and hands each paint
//! over as one of its own GPU buffers (CEF's accelerated paint, a shared texture). The
//! host passes it on, as plain data, to the [`PageSink`] its owner installs, which
//! copies what changed into a texture of its own (bb-render's `UiPage`). bb-ui itself
//! never touches the GPU.
//!
//! Linux's buffers are DMA-BUFs, macOS's IOSurfaces and Windows' D3D11 shared textures
//! (NT handles).

#[cfg(any(target_os = "macos", windows))]
use std::marker::PhantomData;
#[cfg(target_os = "linux")]
use std::os::fd::BorrowedFd;

use super::damage::PaintRect;

/// One plane of a DMA-BUF paint. The fd is the browser's: valid only during the
/// paint's call.
#[cfg(target_os = "linux")]
#[derive(Clone, Copy, Debug)]
pub struct DmaBufPlane<'a> {
	pub fd: BorrowedFd<'a>,
	pub stride: u32,
	pub offset: u64,
	pub size: u64,
}

/// A paint's IOSurface (an `IOSurfaceRef`), the browser's: valid only during the
/// paint's call.
#[cfg(target_os = "macos")]
#[derive(Clone, Copy, Debug)]
pub struct IOSurface<'a> {
	surface: std::ptr::NonNull<std::ffi::c_void>,
	call: PhantomData<&'a ()>,
}

#[cfg(target_os = "macos")]
impl IOSurface<'_> {
	/// # Safety
	/// `surface` is an `IOSurfaceRef` that stays valid for the lifetime given.
	pub(super) unsafe fn new(surface: std::ptr::NonNull<std::ffi::c_void>) -> Self {
		IOSurface { surface, call: PhantomData }
	}

	/// The `IOSurfaceRef`.
	pub fn as_ptr(&self) -> *mut std::ffi::c_void {
		self.surface.as_ptr()
	}
}

/// A paint's D3D11 shared texture (an NT handle), the browser's: valid only during the
/// paint's call.
#[cfg(windows)]
#[derive(Clone, Copy, Debug)]
pub struct D3D11Texture<'a> {
	handle: std::ptr::NonNull<std::ffi::c_void>,
	call: PhantomData<&'a ()>,
}

#[cfg(windows)]
impl D3D11Texture<'_> {
	/// # Safety
	/// `handle` is an NT handle to a shared texture that stays open for the lifetime
	/// given.
	pub(super) unsafe fn new(handle: std::ptr::NonNull<std::ffi::c_void>) -> Self {
		D3D11Texture { handle, call: PhantomData }
	}

	/// The `HANDLE`.
	pub fn as_ptr(&self) -> *mut std::ffi::c_void {
		self.handle.as_ptr()
	}
}

/// The GPU buffer a paint is in.
#[derive(Clone, Copy, Debug)]
pub enum PaintBuffer<'a> {
	/// Linux: a DMA-BUF, with its DRM format modifier (`0x00ffffffffffffff`, none
	/// given: the driver's implicit layout).
	#[cfg(target_os = "linux")]
	DmaBuf { planes: &'a [DmaBufPlane<'a>], modifier: u64 },
	/// macOS: an IOSurface.
	#[cfg(target_os = "macos")]
	IOSurface(IOSurface<'a>),
	/// Windows: a D3D11 shared texture.
	#[cfg(windows)]
	D3D11(D3D11Texture<'a>),
	/// No other operating system's yet.
	#[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
	#[doc(hidden)]
	Unsupported(std::marker::PhantomData<&'a ()>),
}

/// A paint of the page, valid only during [`PageSink::paint`]: the browser takes the
/// buffer back when the call returns.
#[derive(Clone, Copy, Debug)]
pub struct SharedPaint<'a> {
	pub width: u32,
	pub height: u32,
	/// BGRA byte order (else RGBA). Premultiplied either way.
	pub bgra: bool,
	pub buffer: PaintBuffer<'a>,
	/// The parts that changed since the last paint, inside the frame (all of it for the
	/// first paint and after a resize).
	pub dirty: &'a [PaintRect],
}

/// The owner's side of the page's paints: the page's frame on the GPU.
pub trait PageSink: Send + Sync {
	/// Copy `paint`'s dirty rectangles into the page's frame, and finish with the
	/// buffer before returning. Runs on CEF's thread, once per paint.
	fn paint(&self, paint: &SharedPaint) -> Result<(), String>;

	/// The page's frame in `region` (clipped to it): BGRA, premultiplied, rows top to
	/// bottom, with the region as clipped; `None` before the first paint or if nothing
	/// of `region` is on the page. For checking the page's pixels (is the cursor over
	/// the UI) and screenshots: a read from the GPU, so it waits for it.
	fn read(&self, region: PaintRect) -> Result<Option<(PaintRect, Vec<u8>)>, String>;

	/// Chromium switches the paints need to reach this sink, as `(name, value)`, given
	/// when the browser starts (Windows: the GPU adapter to paint on). None by default.
	fn browser_switches(&self) -> Vec<(&'static str, String)> {
		Vec::new()
	}
}

/// The page's frame in memory, for a host without a display or GPU
/// ([`HostConfig::headless`](super::HostConfig)): Chromium's headless platform composites
/// in software and hands each paint over as pixels (`OnPaint`), copied here as they come.
#[derive(Default)]
pub(super) struct MemoryFrame {
	/// Width, height and BGRA pixels, premultiplied, rows top to bottom.
	frame: std::sync::Mutex<(u32, u32, Vec<u8>)>,
}

impl MemoryFrame {
	/// Take a paint: `pixels` is the whole `width` × `height` view, `dirty` what changed.
	pub fn copy(&self, pixels: &[u8], width: u32, height: u32, dirty: &[PaintRect]) {
		let mut frame = self.frame.lock().unwrap_or_else(|e| e.into_inner());
		let stride = width as usize * 4;
		if (frame.0, frame.1) != (width, height) {
			*frame = (width, height, pixels.to_vec());
			return;
		}
		for r in dirty {
			for y in r.y..r.y + r.height {
				let start = y as usize * stride + r.x as usize * 4;
				let end = start + r.width as usize * 4;
				frame.2[start..end].copy_from_slice(&pixels[start..end]);
			}
		}
	}
}

impl PageSink for MemoryFrame {
	fn paint(&self, _paint: &SharedPaint) -> Result<(), String> {
		Err("a headless page is painted in memory, not on the GPU".into())
	}

	fn read(&self, region: PaintRect) -> Result<Option<(PaintRect, Vec<u8>)>, String> {
		let frame = self.frame.lock().unwrap_or_else(|e| e.into_inner());
		let (width, height, pixels) = &*frame;
		let Some(r) = PaintRect::clipped(region.x as i32, region.y as i32, region.width as i32, region.height as i32, *width, *height) else {
			return Ok(None);
		};
		let mut out = Vec::with_capacity((r.width * r.height * 4) as usize);
		for y in r.y..r.y + r.height {
			let start = (y * width + r.x) as usize * 4;
			out.extend_from_slice(&pixels[start..start + r.width as usize * 4]);
		}
		Ok(Some((r, out)))
	}

	/// No GPU at all: Chromium composites and rasterizes in software.
	fn browser_switches(&self) -> Vec<(&'static str, String)> {
		vec![("disable-gpu", String::new()), ("disable-gpu-compositing", String::new())]
	}
}
