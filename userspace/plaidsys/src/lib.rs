#![no_std]
#![feature(panic_info_message,
    asm,
    llvm_asm,
    global_asm,
    const_raw_ptr_to_usize_cast,
    lang_items)]

global_asm!(include_str!("asm/syscall.S"));

pub mod syscall;