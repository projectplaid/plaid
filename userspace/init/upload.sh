#!/bin/bash
sudo mount -o loop ../../kernel/hdd.dsk /mnt
sudo cp target/riscv64gc-unknown-none-elf/debug/init /mnt/init
sudo umount /mnt

