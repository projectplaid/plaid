// Steve Operating System
// Stephen Marz
// 21 Sep 2019
#![no_main]
#![no_std]
#![feature(
    panic_info_message,
    asm,
    llvm_asm,
    global_asm,
    allocator_api,
    alloc_error_handler,
    alloc_prelude,
    const_raw_ptr_to_usize_cast,
    lang_items
)]

// #[macro_use]
extern crate alloc;
// This is experimental and requires alloc_prelude as a feature
// use alloc::prelude::v1::*;

extern crate plaidsys;

// ///////////////////////////////////
// / RUST MACROS
// ///////////////////////////////////
#[macro_export]
macro_rules! print
{
	($($args:tt)+) => ({
			use core::fmt::Write;
			let _ = write!(crate::uart::Uart::new(0x1000_0000), $($args)+);
			});
}
#[macro_export]
macro_rules! println
{
	() => ({
		   print!("\r\n")
		   });
	($fmt:expr) => ({
			print!(concat!($fmt, "\r\n"))
			});
	($fmt:expr, $($args:tt)+) => ({
			print!(concat!($fmt, "\r\n"), $($args)+)
			});
}

// ///////////////////////////////////
// / LANGUAGE STRUCTURES / FUNCTIONS
// ///////////////////////////////////
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    print!("Aborting: ");
    if let Some(p) = info.location() {
        println!(
            "line {}, file {}: {}",
            p.line(),
            p.file(),
            info.message().unwrap()
        );
    } else {
        println!("no information available.");
    }
    abort();
}
#[no_mangle]
extern "C" fn abort() -> ! {
    loop {
        unsafe {
            llvm_asm!("wfi"::::"volatile");
        }
    }
}

extern "C" {
    fn switch_to_user(frame: usize) -> !;
}

/// Switch to user is an assembly function that loads
/// a frame. Since it will jump to another program counter,
/// it will never return back here. We don't care if we leak
/// the stack, since we will recapture the stack during m_trap.
fn rust_switch_to_user(frame: usize) -> ! {
    unsafe {
        switch_to_user(frame);
    }
}
// ///////////////////////////////////
// / ENTRY POINT
// ///////////////////////////////////
#[no_mangle]
extern "C" fn kinit() {
    uart::Uart::new(0x1000_0000).init();

    // try and load the initrd
    let mrom_base: usize = 0x1000;
    unsafe {
        // foo
        let ptr = mrom_base as *mut u32;
        let fdt_start = ptr.add(8);
        println!("fdt start @ 0x{:08p} = 0x{:08x}", fdt_start, *fdt_start);
        let fdt_header = fdt_start as *mut fdt::FdtHeader;
        let result = fdt::check_fdt(fdt_header.as_ref().unwrap());
        match result {
            Ok(_) => {
                println!("Valid FDT");

                println!(
                    "Looking for memory reservation at 0x{:08x}",
                    u32::swap_bytes((*fdt_header).offset_mem_reservation_map) as usize
                );

                // find the reserved memory sections
                let (reservation, next_location) = fdt::fetch_memory_reservation(
                    fdt_start
                        .add(u32::swap_bytes((*fdt_header).offset_mem_reservation_map) as usize)
                        as usize,
                );

                if let Some(r) = reservation {
                    println!("Reservation found: 0x{:08x} of size {}", r.address, r.size);
                }

                if next_location > 0 {
                    println!("Next reservation at 0x{:08x}", next_location);
                }
            }
            Err(e) => {
                println!("Invalid FDT, reason = {:?}", e);
            }
        }
    }

    page::init();
    kmem::init();
    process::init();
    // We lower the threshold wall so our interrupts can jump over it.
    // Any priority > 0 will be able to be "heard"
    plic::set_threshold(0);
    // VIRTIO = [1..8]
    // UART0 = 10
    // PCIE = [32..35]
    // Enable PLIC interrupts.
    for i in 1..=10 {
        plic::enable(i);
        plic::set_priority(i, 1);
    }
    // Set up virtio. This requires a working heap and page-grained allocator.
    virtio::probe();

    console::init();
    process::add_kernel_process(test::test);
    // Get the GPU going
    gpu::init(6);
    // We schedule the next context switch using a multiplier of 1
    // Block testing code removed.
    trap::schedule_next_context_switch(1);
    rust_switch_to_user(sched::schedule());
    // switch_to_user will not return, so we should never get here
}

#[no_mangle]
extern "C" fn kinit_hart(_hartid: usize) {
    // We aren't going to do anything here until we get SMP going.
    // All non-0 harts initialize here.
}

// ///////////////////////////////////
// / RUST MODULES
// ///////////////////////////////////

pub mod assembly;
pub mod block;
pub mod buffer;
pub mod console;
pub mod cpu;
pub mod elf;
pub mod fdt;
pub mod fs;
pub mod gpu;
pub mod input;
pub mod kmem;
pub mod lock;
pub mod page;
pub mod plic;
pub mod process;
pub mod rng;
pub mod sched;
pub mod syscall;
pub mod test;
pub mod trap;
pub mod uart;
pub mod vfs;
pub mod virtio;
