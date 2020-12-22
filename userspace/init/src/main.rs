#![no_std]
#![no_main]
#![feature(const_raw_ptr_to_usize_cast, global_asm)]

#[macro_use]
extern crate plaiduser;

global_asm!(include_str!("asm/start.S"));

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8) -> isize {
    println!("Hello, world!");

    loop {}

    0
}
