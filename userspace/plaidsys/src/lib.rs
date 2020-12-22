#![no_std]
#![feature(llvm_asm, global_asm, const_raw_ptr_to_usize_cast)]

global_asm!(include_str!("asm/syscall.S"));

pub mod syscall;
