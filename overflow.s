
overflow:   .asciiz "Overflow"

# for overflow:
overflow:
la $a0, msg_overflow
li $v0, 4
syscall
li $v0, 10
syscall

# This is a demo for 8 * ( M ^ 3 + N ^ 3)

# (M+0) ^ 3
or $t0, $s0, $zero
add $s0 $s0, $zero 
or $t1, $s0, $zero 
mul $s0, $s0, $s0
or $t2, $s0, $zero 
mul $s0, $t1, $s0
div $s0, $t1
mflo $t3
div $t2, $t1
mflo $t4
#add $t5, $t1, $s1
#overflow
bne $t3, $t2, overflow
bne $t4, $t1, overflow
bne $t5, $t0, overflow


# N ^ 3
or $t0, $s1, $zero
mul $s1, $s1, $s1
or $t1, $s1, $zero
mul $s1, $t0, $s1
or $t2, $s1, $zero
div $t2, $t0
mflo $t4
div $t1, $t0
mflo $t5
#overflow
bne $t3, $t2, overflow
bne $t4, $t1, overflow
bne $t5, $t0, overflow

# 8 * ( M ^ 3 + N ^ 3)
add $s3, $s0, $s1
or $t0, $s3, $zero
# For mul 8, use sll & sra
sll $s3, $s3, 3
sra $t1, $s3, 3
add $t2, $t0, $s1
#overflow
bne $t1, $t0, overflow
bne $t2, $s0, overflow

