	; Game of Life
        ; A 256 Byte intro with MPU401 MIDI "music"
        ; Tested on a 486 with PC MIDI card and Roland SC55
	; (C)2023 A. Schmitz - root42 <root42@root42.de>
	; minified from 250 bytes down to 210 by joonicks <god@joonicks.eu> october 2023

org 0x100
CPU 8086

	old_gen equ 0x40
	new_gen equ 0x50
	StatPort equ 0x331

start:
	; assume ax is 0
	mov dx,0x3c8            ; set palette
	out dx,al               ; write color index (al==0) to VGA
	inc dx                  ; switch to VGA RGB register

	; Setup graphics mode and palette
	mov al,0x13             ; set 320x200x256 mode, assume ah==0
	int 0x10                ; gfx interrupt

	mov al,0x40             ; start with white
initpalette:
	dec ax                  ; -1
	out dx,al               ; write to RGB DAC register
	out dx,al
	out dx,al
	jnz initpalette

;	ax is now 0, assume cx is 0
;	zero out the whole 64k, no need to set di or load cx

        mov ah,old_gen          ; load first buffer into ES
        mov ds,ax
	rep ds stosb            ; clear buffer, al==0

	mov ah,0xa0
	mov gs,ax

	; Reset MPU401
	call mpuIsOutput        ; check if mpu401 is ready
	inc dx
	mov al,0x3f             ; send 'switch to UART' command
	out dx,al               ; write to mpu status port

setup_acorn:
        mov ax,0x0101           ; Bit pattern for two adjacent cells
	mov byte [320*100+161],al
	mov byte [320*101+163],al
	mov word [320*102+160],ax ; write two pixels at once
	mov word [320*102+164],ax ; write two pixels at once
	mov byte [320*102+166],al
        ; Which in turn creates the Acorn start configuration:
        ;
        ; .X.....
        ; ...X...
        ; XX..XXX

mainloop:
        mov dl,0xda             ; input status register (dh==0x03)
	mov cl,2
vsync:
        in al,dx                ; read value
        and al,0x8              ; test vretrace
        jnz vsync               ; wait for retrace to start
	loop vsync

	mov si,0xfa00
	mov dx,ds
	xor dh,0x10
	mov es,dx

process_pixels:
	mov bx,-319		; -0x13f
        mov ax,[si]             ; add up all 8 neighbors ; and al=cell
        add ah,[si-1]
        add ah,[bx+si]		; si-319
        add ah,[bx+si-1]	; si-320
        add ah,[bx+si-2]	; si-321
	neg bx			; bl is now 0x3f for future use
        add ah,[bx+si]
        add ah,[bx+si+1]
        add ah,[bx+si+2]
	; ah = neighbours
	; ah = >=4: kill
	; ah = 3:   create
	; ah = 2:   keep
	; ah <= 1:  kill
	cmp ah,2                ; do we have two neighbors?
	je  short store_cell    ; keep the cell as is
	cmp ah,3                ; do we have three neighbors?
	je  short create_cell   ; then create a new cell!
        xor ax,ax               ; kill the cell
	jmp short store_cell    ; and store value
create_cell:
        mov al,1                ; create new cell
store_cell:
	es mov [si],al
cont_loop:
	inc cx
	mul bl
	jnz copypix
	dec cx
	gs mov al,[si]
	cmp al,0
	je  short copypix
	dec ax
copypix:
	gs mov [si],al
	dec si
	jnz process_pixels

	push es
	pop ds

sound:
	call mpuIsOutput        ; is mpu401 ready?
	mov al,0x90
	out dx,al               ; write to mpu401
	call mpuIsOutput        ; is mpu401 ready?
	and cl,0x7f             ; set 8th bit to 0
	mov al,cl
	out dx,al               ; write to mpu401
	call mpuIsOutput        ; is mpu401 ready?
	mov al,0x7f
	out dx,al               ; write to mpu401

print_msg:
	mov ax,0x1300           ; print, chars only, no cursor move
	; bl is already 0x3f = color black
	mov cl,greetlen         ; number of chars, ch==0
	mov dl,0x10             ; row 3, column 17 (centered), dh==3
	push cs                 ; move CS to ES
	pop es
	mov bp,greet            ; load offset for greeting into BP
	int 0x10                ; call display interrupt

check_key:
	in al,0x60              ; read keyboard
	dec al                  ; ESC has scancode 1
	jnz mainloop            ; if not zero, ESC wasn't pressed

key_pressed:
	mov ax,0x03             ; set text mode
	int 0x10                ; gfx interrupt
	int 0x20                ; return to DOS (ret doesn't work due
				; to things on the stack)

mpuIsOutput:
        mov dx,0x0331           ; status port 0x331, dh=0x03
	in al,dx                ; read status byte
	and al,0x40             ; 7th bit is output busy
	jnz short mpuIsOutput   ; no? try again. might hang on incompatible hardware
	dec dx
	ret

greet:
	db 0x03,"root42",0x03   ; string to output
        greetlen equ 8
