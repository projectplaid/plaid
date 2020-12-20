# plaid kernel

Working on a RISC-V 64 kernel, based on the [fantastic blog series](https://osblog.stephenmarz.com/index.html) by Stephen Marz.

All work is MIT licensed, with original work Copyright (c) 2019 Stephen Marz.

New work is Copyright (c) 2020 Robert Roland.

## Building

### Prerequisites

This uses several features from the `nightly` Rust distributions.

```bash
rustup default nightly
rustup target add riscv64gc-unknown-none-elf
cargo install cargo-binutils
```

### Building

Edit `.cargo/config` to match your host's configuration. The runner will execute when you type `cargo run`.

Type `cargo build` to start the build process. Type `cargo run` to run using the runner provided in `.cargo/config`

### Hard disk image

Create a new image:

```bash
fallocate -l 32M hdd.dsk
mkfs.minix -3 ./hdd.dsk
```

### Userspace programs

You need, at minimum, the `shell` from the `userspace` folder.

```bash
cd userspace
make
sudo ./upload.sh shell
```

This will copy the `shell` binary into the disk image created above.
