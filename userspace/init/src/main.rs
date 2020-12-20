#![no_std]
#![no_main]
#![feature(panic_info_message,
           asm,
		   llvm_asm,
           global_asm,
		   const_raw_ptr_to_usize_cast,
		   lang_items)]

#[macro_use]
extern crate plaidsys;

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8) -> isize {
    println!("Hello, world!");

    0
}
