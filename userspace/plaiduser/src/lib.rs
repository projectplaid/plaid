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

// pub extern crate alloc;

// pub extern crate ralloc;

// #[global_allocator]
// static ALLOCATOR: ralloc::Allocator = ralloc::Allocator;

// pub extern crate plaidsys;

// use alloc::string::String;
use core::intrinsics::abort;

#[lang = "eh_personality"]
extern "C" fn eh_personality() {}

// ///////////////////////////////////
// / RUST MACROS
// ///////////////////////////////////
#[macro_export]
macro_rules! print {
    ($($args:tt)+) => {{
        // use core::fmt::Write;

        // let mut s = String::new();
        // let _ = write!(&mut s, $($args)+);

        // plaidsys::syscall::syscall_write(1, s.as_ptr(), s.len());
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
