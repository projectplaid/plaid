#![no_std]
#![feature(
    panic_info_message,
    asm,
    core_intrinsics,
    llvm_asm,
    global_asm,
    const_raw_ptr_to_usize_cast,
    lang_items
)]

use core::intrinsics::abort;

extern crate plaidsys;

#[lang = "eh_personality"]
extern "C" fn eh_personality() {}

// ///////////////////////////////////
// / RUST MACROS
// ///////////////////////////////////
#[macro_export]
macro_rules! print {
    ($($args:tt)+) => {{
        // use core::fmt::Write;
        // let _ = write!(crate::uart::Uart::new(0x1000_0000), $($args)+);
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
