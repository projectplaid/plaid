.section .text

.global make_syscall
make_syscall:
	# We're setting this up to work with libgloss
	# They want a7 to be the system call number and all parameters
	# in a0 - a5
	mv	a7, a0
	mv	a0, a1
	mv	a1, a2
	mv	a2, a3
	mv	a3, a4
	mv	a4, a5
	mv	a5, a6
	ecall
	ret
