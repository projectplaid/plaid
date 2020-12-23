#![no_std]
#![feature(
    panic_info_message,
    asm,
    core_intrinsics,
    llvm_asm,
    global_asm,
    const_raw_ptr_to_usize_cast,
    lang_items,
    default_alloc_error_handler
)]

pub extern crate alloc;

pub mod bump;

use bump::{BumpAllocator, Locked};

#[global_allocator]
static ALLOCATOR: Locked<BumpAllocator> = Locked::new(BumpAllocator::new());

#[no_mangle]
extern "C" fn user_init() {
    unsafe {
        ALLOCATOR.lock().init();
    }
}

pub extern crate plaidsys;

#[lang = "eh_personality"]
extern "C" fn eh_personality() {}

// ///////////////////////////////////
// / RUST MACROS
// ///////////////////////////////////
#[macro_export]
macro_rules! print {
    ($($args:tt)+) => {{
        use alloc::string::String;
        use core::fmt::Write;

        let mut s = String::new();

        let _ = write!(&mut s, $($args)+);
        plaidsys::syscall::do_make_syscall(64, 0, 0, 0, 0, 0, 0);

        plaidsys::syscall::syscall_write(1, s.as_ptr(), s.len());
    }};
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

#[no_mangle]
extern "C" fn abort() -> ! {
    loop {
        unsafe {
            llvm_asm!("wfi"::::"volatile");
        }
    }
}

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
