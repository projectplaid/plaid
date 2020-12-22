//! **Ralloc:** The memory efficient allocator.
//!
//! This crates define the user space allocator for Redox, which emphasizes performance and memory
//! efficiency.
//!
//! # Ralloc seems to reimplement everything. Why?
//!
//! Memory allocators cannot depend on libraries or primitives, which allocates. This is a
//! relatively strong condition, which means that you are forced to rewrite primitives and make
//! sure no allocation ever happens.

#![cfg_attr(feature = "clippy", feature(plugin))]
#![cfg_attr(feature = "clippy", plugin(clippy))]
#![no_std]
#![feature(
    allocator_api,
    const_fn,
    core_intrinsics,
    stmt_expr_attributes,
    type_ascription,
    thread_local,
    linkage
)]
#![warn(missing_docs)]

extern crate ralloc_shim as shim;

#[macro_use]
mod log;
#[macro_use]
#[cfg(feature = "tls")]
mod tls;

#[macro_use]
mod unborrow;

mod allocator;
mod block;
mod bookkeeper;
mod brk;
mod cell;
mod fail;
mod lazy_init;
mod leak;
mod prelude;
mod ptr;
mod sync;
mod vec;

use core::alloc::{GlobalAlloc, Layout};

pub use allocator::{alloc, free, realloc, realloc_inplace};
pub use brk::sbrk;
pub use fail::set_oom_handler;
#[cfg(feature = "tls")]
pub use fail::set_thread_oom_handler;

/// The rallocator
pub struct Allocator;

unsafe impl GlobalAlloc for Allocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        allocator::alloc(layout.size(), layout.align())
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        allocator::free(ptr, layout.size());
    }
}
