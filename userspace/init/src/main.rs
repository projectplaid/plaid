#![no_std]
#![no_main]
#![feature(const_raw_ptr_to_usize_cast)]

#[macro_use]
extern crate plaiduser;

#[no_mangle]
pub extern "C" fn main(_argc: isize, _argv: *const *const u8) -> isize {
    println!("Hello, world!");

    0
}
