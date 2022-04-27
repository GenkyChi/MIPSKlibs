
# temp registers conventions:
# t0:		temp operand
# t1 - t3:	local variables
# t4:		counter
# t5:		local result
# t6 - t7:	temp address
# t8 - t9:	local constants

.data

	.align	4

	# const data

	hex_dict:			.ascii  "01234567890abcdef"
	hex_prefix:			.asciiz "0x"

	msg_panic:			.asciiz "panic at "

	msg_err_canary:		.asciiz "overflow in data section detected"
	msg_err_invchr:		.asciiz "invalid character"
	msg_err_blkstr:		.asciiz "blank string"
	msg_err_intof:		.asciiz "overflow"
	msg_err_invstr:		.asciiz "invalid string"
	msg_err_tpmismtch:	.asciiz "template mismatch"

	str_colon:			.asciiz ": "

	str_input_tp1:		.asciiz "P1:\"%\";"
	str_input_tp2:		.asciiz "P2:\"%\";"
	str_input_tp3:		.asciiz "P3:%;"

	input_buf:			.space	0x10000
	tmp_buf:			.space	0x10000
	src_buf:			.space	0x10000
	dst_buf:			.space	0x10000

	test_str:			.asciiz "P1:\"1\t345\t78\";P2:\"a\ncdefgh\";P3:5"

	# canary is implemented to detect overflow in data section
	canary:				.word	0xEFCDBA00

# end data section



.text

# printhex(unsigned int value)
printhex:

	move	$t0, $a0

	# puts("0x")
	la		$a0, hex_prefix
	li		$v0, 4
	syscall

	# cnt = 4
	li		$t4, 0x10000000		# $t4 = 4

	loop_printhex: # while (cnt > 0)

		beq		$t4, $zero,	endloop_printhex

		divu	$t0, $t4			# $t0 / $t4
		mflo	$t2					# $t0 = floor($t0 / $t4) 
		mfhi	$t0					# $t2 = $t0 mod $t4

		la		$t6, hex_dict
		add		$t6, $t6, $t2		# $t6 = $t6 + $t2
		
		# putch(*t6)
		lbu		$a0, ($t6)
		li		$v0, 11
		syscall

		srl		$t4, $t4, 4			# $t4 = $t4 >> 4

		j		loop_printhex

	endloop_printhex:

	jr $ra

# end func printhex



# panic(char*)
#   char* msg: $a0
panic:

	move	$s0, $a0

	# puts("panic at")
	la		$a0, msg_panic
	li		$v0, 4
	syscall

	move	$a0, $ra
	jal		printhex			# jump to printhex and save position to $ra

	# puts(": ")
	la		$a0, str_colon
	li		$v0, 4
	syscall

	# puts(msg)
	move	$a0, $s0
	li		$v0, 4
	syscall

	li		$a0, 10
	li		$v0, 11
	syscall

	# exit
	li		$v0, 10
	syscall

# end func panic



# chk_canary
chk_canary:

	la		$t6, canary
	lw		$t1, ($t6)

	# little endian
	li		$t0, 0xEFCDAB00			# $t0 = 0xEFCDAB00
	beq		$t1, $t0, chk_failed	# if $t1 == $t0 then target
	
	jr		$ra						# jump to $ra
	
	chk_failed:

		la		$a0, msg_err_canary
		jal		panic				# jump to panic and save position to $ra

# end chk_canary



# parse_int(char*) -> int
#   char* s: $a0
#   return : $v0
parse_int:
	
	move	$t6, $a0

	# t5: result
	li		$t5, 0
	# const c0 = '0'
	li		$t8, 48
	# const c9 = '9'
	li		$t9, 56

	# int c = t6
	lbu		$t1, ($t6)

	li		$t0, 10						# $t0 = '\n'
	beq		$t1, $t0,	err_blkstr_parse_int
	beq		$t1, $zero,	err_blkstr_parse_int

	loop_parse_int: # while (*s)

		lbu		$t1, ($t6)

		li		$t0, 10						# $t0 = '\n'
		beq		$t1, $t0,	rt_parse_int	# if $t1 == '\n' then rt_parse_int
		beq		$t1, $zero,	rt_parse_int	# if $t1 == $zero then rt_parse_int

		blt		$t1, $t8,	err_invchr_parse_int		# if $t1 < '0' then err_invchr
		bgt		$t1, $t9,	err_invchr_parse_int		# if $t1 > '9' then err_invchr
		
		li		$t0, 10				# $t0 = 10
		mult	$t5, $t0			# $t5 * 10 = Hi and Lo registers
		mflo	$t5					# copy Lo to $t5

		sub		$t1, $t1, $t8		# $t1 = $t1 - '0'
		add		$t5, $t5, $t1		# $t5 = $t5 + $t1
		
		# ptr++
		add		$t6, $t6, 1

		j		loop_parse_int
			
	endloop_parse_int:

	err_invchr_parse_int:

		la		$a0,	msg_err_invchr
		jal		panic				# jump to panic and save position to $ra

	err_blkstr_parse_int:

		la		$a0,	msg_err_blkstr
		jal		panic				# jump to panic and save position to $ra
	
	rt_parse_int:

		# return t5
		move	$v0, $t5
		jr		$ra					# jump to $ra
	
# end func parse_int


# parse_hex(char* s, int n)
# parse a hex char seq like `D34DBEEF`
parse_hex:

	move	$t6, $a0
	move	$t4, $a1

	# t5: result
	li		$t5, 0

	# int c = t6
	lbu		$t1, ($t6)

	li		$t0, 10						# $t0 = '\n'
	beq		$t1, $t0,	err_blkstr_parse_hex
	beq		$t1, $zero,	err_blkstr_parse_hex

	loop_parse_hex: # while (*s && t-- > 0)

		li		$t0, 0
		ble		$t4, $t0,	rt_parse_hex		# if $t4 == $t0 then rt_parse_hex
		
		lbu		$t1, ($t6)

		li		$t0, 10									# $t0 = '\n'
		beq		$t1, $t0,	rt_parse_hex				# if $t1 == '\n' then rt_parse_int
		beq		$t1, $zero,	rt_parse_hex				# if $t1 == $zero then rt_parse_int

		li		$t0, 97									# $t0 = 97
		bge		$t1, $t0, 	b_parse_chr_hex_digit_lower	# if $t1 >= $t0 then b_parse_chr_hex_digit_lower
		
		li		$t0, 65									# $t0 = 65
		bge		$t1, $t0, 	b_parse_chr_hex_digit_upper	# if $t1 >= $t0 then b_parse_chr_hex_digit_upper

		li		$t0, 48									# $t0 = 48
		bge		$t1, $t0, 	b_parse_chr_dec_digit		# if $t1 >= $t0 then b_parse_chr_dec_digit
		

	b_parse_chr_hex_digit_upper:
		
		li		$t0, 70									# $t0 = 70
		bgt		$t1, $t0,	err_invchr_parse_hex		# if $t1 > 'F' then err_invchr_parse_hex

		li		$t0, 16				# $t0 = 16
		mult	$t5, $t0			# $t5 * 16 = Hi and Lo registers
		mflo	$t5					# copy Lo to $t5

		li		$t0, 55				# $t0 = 55
		sub		$t1, $t1, $t8		# $t1 = $t1 - 'A' + 10
		add		$t5, $t5, $t1		# $t5 = $t5 + $t1

		j		continueloop_parse_hex

	b_parse_chr_hex_digit_lower:

		li		$t0, 102								# $t0 = 102
		bgt		$t1, $t0,	err_invchr_parse_hex		# if $t1 > 'f' then err_invchr_parse_hex

		li		$t0, 16				# $t0 = 16
		mult	$t5, $t0			# $t5 * 16 = Hi and Lo registers
		mflo	$t5					# copy Lo to $t5

		li		$t0, 87				# $t0 = 87
		sub		$t1, $t1, $t8		# $t1 = $t1 - 'a' + 10
		add		$t5, $t5, $t1		# $t5 = $t5 + $t1

		j		continueloop_parse_hex

	b_parse_chr_dec_digit:
		
		li		$t0, 57									# $t0 = 57
		bgt		$t1, $t0,	err_invchr_parse_hex		# if $t1 > '9' then err_invchr_parse_hex

		li		$t0, 16				# $t0 = 16
		mult	$t5, $t0			# $t5 * 16 = Hi and Lo registers
		mflo	$t5					# copy Lo to $t5

		sub		$t1, $t1, $t8		# $t1 = $t1 - '0'
		add		$t5, $t5, $t1		# $t5 = $t5 + $t1

		j		continueloop_parse_hex

	continueloop_parse_hex:
		
		# ptr++
		add		$t6, $t6, 1
		add		$t4, $t4, -1
		j		loop_parse_hex
			
	endloop_parse_hex:

	err_invchr_parse_hex:

		la		$a0,	msg_err_invchr
		jal		panic				# jump to panic and save position to $ra

	err_blkstr_parse_hex:

		la		$a0,	msg_err_blkstr
		jal		panic				# jump to panic and save position to $ra
	
	rt_parse_hex:

		# return t5
		move	$v0, $t5
		jr		$ra					# jump to $ra

# end parse_hex



# safe_mul(int x, int y) -> int
safe_mul:

	move	$t1, $a0
	move	$t2, $a1

	mult	$t1, $t2			# $t1 * $t2 = Hi and Lo registers
	mflo	$t5					# copy Lo to $t5
	mfhi	$t3

	# judge if t3 is 0x00000000 or 0xffffffff
	beq		$t3, $zero,	rt_safe_mul	# if $t3 == $zero then rt_safe_mul
	li		$t0, 0xffffffff			# $t0 = 0xffffffff
	beq		$t3, $t0,	rt_safe_mul	# if $t3 == $t0 then rt_safe_mul

	# else means overflow
	la		$a0, msg_err_intof
	jal		panic				# jump to panic and save position to $ra

	rt_safe_mul:

		move	$v0, $t5
		jr		$ra

# end func safe_mul



# stresc(char* dst, char* src)
# solve escape characters
stresc:

	# t6 = src, t7 = dst
	move 	$t7, $a0
	move 	$t6, $a1
	li		$t8, 92			# $t8 = '\\'

	loop_stresc: # while (*src)

		# unsigned int c = *src
		lbu		$t1, ($t6)

		beq		$t1, $zero,	rt_stresc

		beq		$t1, $t8,	b_esc_chr		# if $t1 == '\\' then b_esc_chr
		sb		$t1, ($t6)

	c_loop_stresc:

		addi	$t6, $t6, 1			# $t6 = $t6 + 1
		addi	$t7, $t7, 1			# $t7 = $t7 + 1

		j		loop_stresc

	b_esc_chr:

		lbu		$t2, 1($t6)				# look forward

		addi	$t6, $t6, 1				# $t6 = $t6 + 1

		li		$t0, 120				# $t0 = 'x'
		beq		$t0, $t2, b_esc_hex		# if $t0 == $t1 then target

		li		$t0, 110				# $t0 = 'n'
		beq		$t0, $t2, b_esc_slh_n	# if $t0 == $t1 then target

		li		$t0, 116				# $t0 = 't'
		beq		$t0, $t2, b_esc_slh_t	# if $t0 == $t1 then target

		li		$t0, 114				# $t0 = 'r'
		beq		$t0, $t2, b_esc_slh_r	# if $t0 == $t1 then target
		
		# '\\' cannot be the last character of a string
		lbu		$t0, ($t6)
		beq		$t0, $zero,	err_invstr	# if $t0 == $zero then err_invstr
		
		j		loop_stresc
	
	b_esc_hex:

		# skip `x`
		addi	$t6, $t6, 1				# $t6 = $t6 + 1
		
		move	$a0, $t6
		li		$a1, 2

		move	$s6, $t6
		move	$s7, $t7

		sw		$ra, ($sp)
		addi	$sp, $sp, 4
		jal		parse_hex
		lw		$ra, -4($sp)
		addi	$sp, $sp, -4

		move	$t6, $s6
		move	$t7, $s7

		addi	$t6, $t6, 2
		j		loop_stresc
		
	b_esc_slh_n:

		li		$t1, 10		# $t1 = LF
		j		c_loop_stresc

	b_esc_slh_r:

		li		$t1, 13		# $t1 = CR
		j		c_loop_stresc

	b_esc_slh_t:

		li		$t1, 9		# $t1 = TAB
		j		c_loop_stresc

	endloop_stresc:

	err_invstr:

		la		$a0,	msg_err_invstr
		jal		panic

	rt_stresc:

		sw		$ra, ($sp)
		addi	$sp, $sp, 4
		jal		chk_canary
		lw		$ra, -4($sp)
		addi	$sp, $sp, -4
		jr		$ra

# stresc



# memset(void* ptr, unsigned char byte, size_t size)
memset:

	move	$t6, $a0
	move	$t8, $a1
	move	$t4, $a2

	loop_memset:

		beq		$t4, $zero, rt_memset	# if $t4 == $zero then rt_memset
		sb		$t8, ($t6)
		addi	$t6, $t6, 1			# $t6 = $t6 + 1
		addi	$t4, $t4, -1		# $t4 = $t4 - 1
		j		loop_memset

	endloop_memset:

	rt_memset:

		sw		$ra, ($sp)
		addi	$sp, $sp, 4
		jal		chk_canary
		lw		$ra, -4($sp)
		addi	$sp, $sp, -4
		jr		$ra

# end func memset



# strncpy(char* dst, char* src, size_t n)
#
#	char* strncpy (char *s1, const char *s2, size_t n)
#	{
#		size_t size = __strnlen (s2, n);
#		if (size != n)
#			memset (s1 + size, '\0', n - size);
#		return memcpy (s1, s2, size);
#	}
#
strncpy:
	
	move 	$s1, $a0
	move 	$s2, $a1
	move	$s3, $a2

	move 	$a1, $zero

	sw		$ra, ($sp)
	addi	$sp, $sp, 4
	jal		memset
	lw		$ra, -4($sp)
	addi	$sp, $sp, -4

	# t6 = src, t7 = dst
	move 	$t7, $s1
	move 	$t6, $s2
	move	$t4, $s3

	loop_strncpy: # while (*src)

		# unsigned int c = *src
		lbu		$t1, ($t6)

		beq		$t4, $zero,	rt_strncpy
		beq		$t1, $zero,	rt_strncpy

		# beq		$t1, $t8,	skip_chr		# if $t1 == '\\' then skip_chr
		sb		$t1, ($t7)

		addi	$t6, $t6, 1			# $t6 = $t6 + 1
		addi	$t7, $t7, 1			# $t7 = $t7 + 1

		addi	$t4, $t4, -1		# $t4 = $t4 - 1

		j		loop_strncpy

	endloop_strncpy:

	rt_strncpy:

		sw		$ra, ($sp)
		addi	$sp, $sp, 4
		jal		chk_canary
		lw		$ra, -4($sp)
		addi	$sp, $sp, -4
		jr		$ra

# end func strncpy



# strchr(char* s, const char c) -> char*
# find the first char c in string s
strchr:

	move	$t6, $a0
	move	$t8, $a1

	loop_strchr:

		lbu		$t1, ($t6)
		beq		$t1, $t8, rt_strchr	# if $t1 == $t8 then rt_strchr
		
		# s++
		addi	$t6, $t6, 1			# $t6 = $t6 + 1
		j		loop_strchr

	rt_strchr:

		move	$v0, $t6
		jr		$ra					# jump to $ra

# end func strchr



# parse_template(char* tp, char* s, char* dst)
#	-> char* end
parse_template:

	move	$t6, $a0
	move	$t7, $a1
	move	$t8, $a2

	loop_parse_template_before:

		lbu		$t1, ($t6)
		lbu		$t2, ($t7)

		li		$t0, 37				# t0 = '%'
		beq		$t1, $t0, endloop_parse_template_before

		bne		$t1, $t2, err_template_mismatch	# if $t1 != $t2 then err_template_mismatch

		addi	$t6, $t6, 1			# $t6 = $t6 + 1
		addi	$t7, $t7, 1			# $t6 = $t6 + 1

		j		loop_parse_template_before

	endloop_parse_template_before:

	move	$v0, $t7

	addi	$t6, $t6, 1
	lbu		$t1, ($t6)
	move	$t9, $t1		# t9 = next character after '%'

	loop_parse_template_matching:

		lbu		$t2, ($t7)
		
		beq		$t2, $t9, endloop_parse_template_matching
		sw		$t2, ($t8)

		addi	$t7, $t7, 1			# src++
		addi	$t8, $t8, 1			# dst++

		j		loop_parse_template_matching

	endloop_parse_template_matching:

	sw		$zero, 1($t8)

	loop_parse_template_after:

		lbu		$t1, ($t6)
		lbu		$t2, ($t7)

		beq		$t1, $zero,	rt_parse_template
		bne		$t1, $t2,	err_template_mismatch	# if $t1 != $t2 then err_template_mismatch

		addi	$t6, $t6, 1			# tp++
		addi	$t7, $t7, 1			# src++

		j		loop_parse_template_after

	endloop_parse_template_after:

	err_template_mismatch:

		la		$a0,	msg_err_tpmismtch
		jal		panic				# jump to panic and save position to $ra

	rt_parse_template:

		move	$v0, $t7
		jr		$ra					# jump to $ra

# end func parse_template



# entry

.globl main

main:


