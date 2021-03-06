pub struct Send {}

/// IPC Syscall definitions
/// This follow a similar structure to seL4 (the gold standard in good microkernels)

pub fn syscall_send() {}

pub fn syscall_nonblocking_send() {}

pub fn syscall_wait() {}

pub fn syscall_nonblocking_wait() {}

pub fn syscall_call() {}

pub fn syscall_receive() {}

pub fn syscall_reply() {}

pub fn syscall_reply_receive() {}

pub fn syscall_nonblocking_receive() {}

pub fn syscall_yield() {
    let _ = do_make_syscall(1, 0, 0, 0, 0, 0, 0);
}

extern "C" {
    fn make_syscall(
        sysno: usize,
        arg0: usize,
        arg1: usize,
        arg2: usize,
        arg3: usize,
        arg4: usize,
        arg5: usize,
    ) -> usize;
}

pub fn do_make_syscall(
    sysno: usize,
    arg0: usize,
    arg1: usize,
    arg2: usize,
    arg3: usize,
    arg4: usize,
    arg5: usize,
) -> usize {
    unsafe { make_syscall(sysno, arg0, arg1, arg2, arg3, arg4, arg5) }
}

pub fn syscall_exit() {
    let _ = do_make_syscall(93, 0, 0, 0, 0, 0, 0);
}

pub fn syscall_execv(path: *const u8, argv: usize) -> usize {
    do_make_syscall(11, path as usize, argv, 0, 0, 0, 0)
}

pub fn syscall_fs_read(dev: usize, inode: u32, buffer: *mut u8, size: u32, offset: u32) -> usize {
    do_make_syscall(
        63,
        dev,
        inode as usize,
        buffer as usize,
        size as usize,
        offset as usize,
        0,
    )
}

pub fn syscall_block_read(dev: usize, buffer: *mut u8, size: u32, offset: u32) -> u8 {
    do_make_syscall(
        180,
        dev,
        buffer as usize,
        size as usize,
        offset as usize,
        0,
        0,
    ) as u8
}

pub fn syscall_sleep(duration: usize) {
    let _ = do_make_syscall(10, duration, 0, 0, 0, 0, 0);
}

pub fn syscall_get_pid() -> u16 {
    do_make_syscall(172, 0, 0, 0, 0, 0, 0) as u16
}

pub fn syscall_sbrk(addr: *const u8) -> *const u8 {
    do_make_syscall(214, addr as usize, 0, 0, 0, 0, 0) as *const u8
}

pub fn syscall_write(fd: i32, addr: *const u8, size: usize) -> usize {
    do_make_syscall(64, fd as usize, addr as usize, size as usize, 0, 0, 0) as usize
}

pub fn syscall_breakpoint() {}
