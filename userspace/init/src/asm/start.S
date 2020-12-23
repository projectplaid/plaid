
.section .text.init

.global _start
_start:
  # Initialize global pointer
.option push
.option norelax
1:	auipc 	gp, %pcrel_hi(__global_pointer$)
  	addi  	gp, gp, %pcrel_lo(1b)
.option pop

	# Set all bytes in the BSS section to zero.
	la 		a0, __bss_start
	la		a1, __BSS_END__
	bgeu	a0, a1, 2f
1:
	sd		zero, (a0)
	addi	a0, a0, 8
	bltu	a0, a1, 1b
2:
	call	user_init

	lw      a0, 0(sp)                  # a0 = argc
	addi    a1, sp, 8				   # a1 = argv
	li      a2, 0                      # a2 = envp = NULL
	call    main

	# Exit system call after main
	li		a0, 93
	j 		make_syscall
.type _start, function
.size _start, .-_start

  .global _init
  .type   _init, @function
  .global _fini
  .type   _fini, @function
_init:
_fini:
  # These don't have to do anything since we use init_array/fini_array.
  ret
  .size  _init, .-_init
  .size  _fini, .-_fini
