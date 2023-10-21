	; Game of Life
        ; A 256 Byte intro with MPU401 MIDI "music"
        ; Tested on a 486 with PC MIDI card and Roland SC55
	; (C)2023 A. Schmitz - root42 <root42@root42.de>
org 0x100
CPU 8086

	old_gen equ 0x40
	new_gen equ 0x50
	StatPort equ 0x331

start:
	; Setup graphics mode and palette
	mov al,0x13             ; set 320x200x256 mode, assume ah==0
	int 0x10                ; gfx interrupt
	mov dx,0x3c8            ; set palette
	xor al,al               ; color index 0
	out dx,al               ; write color index to VGA
	inc dx                  ; switch to VGA RGB register
	mov cl,0x40             ; start with white
	mov al,cl               ; load current value
initpalette:
	dec al                  ; -1
	out dx,al               ; write to RGB DAC register
	out dx,al
	out dx,al
        ; Assuming the direction bit is cleared, seems to be the case
	; always
	loop initpalette

        mov ch,old_gen          ; load first buffer into ES
        mov es,cx
	mov ch,0xFA             ; number of bytes in buffer, cl=00
	xor di,di               ; clear destination index
	rep stosb               ; clear buffer, al==0
	push es                 ; put old buf ptr also into DS
	pop ds
        mov ch,new_gen          ; push second buffer on stack
        push cx

	; Reset MPU401
	call mpuIsOutput        ; check if mpu401 is ready
	mov al,0x3f             ; send 'switch to UART' command
	out dx,al               ; write to mpu status port

setup_acorn:
        mov ax,0x0101           ; Bit pattern for two adjacent cells
        mov di,320*100+161      ; first cell is here!
        stosb                   ; store it
        add di,321              ; skip to next line
        stosb                   ; store cell
        add di,316              ; skip to next line
        stosw                   ; store two cells
        inc di                  ; skip two cells
        inc di
        stosw                   ; store two cells
        stosb                   ; store one cell
        ; This is equivalent to the following:
	; mov byte [320*100+161],0x01
	; mov byte [320*101+163],0x01
	; mov word [320*102+160],0x0101 ; write two pixels at once
	; mov word [320*102+164],0x0101 ; write two pixels at once
	; mov byte [320*102+166],0x01
        ; Which in turn creates the Acorn start configuration:
        ;
        ; .X.....
        ; ...X...
        ; XX..XXX

mainloop:

doretrace:
        mov dl,0xda             ; input status register (dh==0x03)
wait1:
        in al,dx                ; read value
        and al,0x8              ; test vretrace
        jnz wait1               ; wait for retrace to start
wait2:
        in al,dx                ; read value
        and al,0x8              ; test vretrace
        jz wait2                ; wait for retrace to stop

	mov ch,0xfa             ; iterate over all pixels, cl=00
	pop es                  ; fetch other buffer from stack

process_pixels:
	mov si,cx               ; load current pixel position
        mov ah,[si-1]           ; add up all 8 neighbors
        add ah,[si+1]
        add ah,[si-321]
        add ah,[si-320]
        add ah,[si-319]
        add ah,[si+319]
        add ah,[si+320]
        add ah,[si+321]
	mov di,cx               ; take current loc
	cmp ah,3                ; do we have three neighbors?
	je short create_cell    ; then create a new cell!
	cmp ah,2                ; do we have two neighbors?
	je short keep_cell      ; keep the cell as is
        xor al,al               ; kill the cell
	jmp short store_cell    ; and store value
create_cell:
        mov al,1                ; create new cell
	jmp short store_cell    ; and store value
keep_cell:
        lodsb                   ; load cell as it is
store_cell:
        stosb                   ; store value for cell
cont_loop:
	loop  process_pixels    ; dec cx, jump to loop start


copy_screen:
        push es                 ; put ES on stack for later swap
        mov ch,0xa0             ; load VGA mem ptr into ES
        mov es,cx               ; assume cl==0x00
        xor bl,bl               ; temp note buffer
	xor si,si               ; clear source
	xor di,di               ; clear destination
	mov ch,0xfa             ; number of pixels to copy, cl=00
copyloop:
	lodsb                   ; load pixel
	test al,1               ; is pixel 0?
	jnz setpix              ; not 0, then set pixel fresh
	; FIXME: can we replace this with scasb? the inc di is
	; annoying...
	es mov al,[di]          ; load current pixel
	cmp al,0                ; is pixel 0?
	je short continue_copy  ; then do nothing
	dec al                  ; else decrement pixel
	jmp short continue_copy
setpix:
        inc bl                  ; increment note count
	mov al,0x3f             ; new cell starts off at 63
continue_copy:
	stosb
	loop copyloop           ; iterate
sound:
        mov cl,3                ; three notes
        mov si,sounddata        ; load pointer to MIDI data
        and bl,0x7f             ; set 8th bit to 0
        cs mov [sounddata+1],bl ; write counterto pitch data
w1:
	call mpuIsOutput        ; is mpu401 ready?
	dec dx                  ; go to data port
        cs lodsb                ; load next data
	out dx,al               ; write to mpu401
        loop w1
print_msg:
	mov ax,0x1300           ; print, chars only, no cursor move
	mov bl,0x3f             ; color black, bh==0
	mov cl,greetlen         ; number of chars, ch==0
	mov dl,0x10             ; row 3, column 17 (centered), dh==3
	push es                 ; save ES
	push cs                 ; move CS to ES
	pop es
	mov bp,greet            ; load offset for greeting into BP
	int 0x10                ; call display interrupt
	pop es                  ; restore value of ES
swap_buffers:
	; swap source and target
	pop cx                  ; fetch other buffer from stack
	push ds                 ; push current buffer on stack
	mov ds,cx               ; load next buffer into DS

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
        mov dl,0x31             ; status port 0x331, dh=0x03
	in al,dx                ; read status byte
	and al,0x40             ; 7th bit is output busy
	jnz short mpuIsOutput   ; no? try again. might hang on incompatible hardware
	ret

sounddata:
	db 0x90                 ; 1001xxxx note on xxxx=channel -> 0
note:
	db 0x20                 ; dummy pitch 0ppppppp, p=0..127
	db 0x7f                 ; velocity 0vvvvvvv, v=0..127

greet:
	db 0x03,"root42",0x03   ; string to output
        greetlen equ 8
