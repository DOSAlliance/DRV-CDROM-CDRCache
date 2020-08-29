 ; This file is part of CDRcache, the 386/XMS DOS CD-ROM cache by
 ; Eric Auer (eric@coli.uni-sb.de), based on LBAcache, 2001-2003.

 ; CDRcache is free software; you can redistribute it and/or modify
 ; it under the terms of the GNU General Public License as published
 ; by the Free Software Foundation; either version 2 of the License,
 ; or (at your option) any later version.

 ; CDRcache is distributed in the hope that it will be useful,
 ; but WITHOUT ANY WARRANTY; without even the implied warranty of
 ; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ; GNU General Public License for more details.

 ; You should have received a copy of the GNU General Public License
 ; along with CDRcache; if not, write to the Free Software Foundation,
 ; Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 ; (or try http://www.gnu.org/licenses/licenses.html at www.gnu.org).

 ; -------------------------------------------------------------------

%define SYNDEBUG 1	; show error numbers for syntax errors

	; Some of the status messages use meep: This uses
	; int 21 while running < 1 and int 10 tty otherwise.

	; parse command line and display it, normally returning NC
	; input: pointer to "that device thing"
	; syntax: cdrom-driver-device-name our-device-name size
	;   size unit is 128 sectors. size must have 1-2 digits.
	;   initial ?:\... (up to space) is skipped, as device
	;   name can be part of the device command line.
	;   *** changed: initial anything is skipped, even if no
	;   *** drive letter is given (12.10.2003). Only for .sys!
	;   (fixes bug: "device=c:\file" worked, "device=file" not!)
	; syntax error causes help message display and returns CY.

parsecommandline:
	push es
	push bx
	push eax
	push si
	les bx,[es:bx+0x12]	; here comes our pointer :-)

	; warning: StrTTY trashes registers: BX AX SI...

%ifdef DBGclptr
		mov ax,es
		push word clbufend	; empty silence *offset*
		call meep		; show es
		mov ax,bx
		push word clbufend	; empty silence *offset*
		call meep		; show bx
%endif

; -------------

				; syntax error 1: no arguments
	jmp clignore_initial	; *** completely ignore first word!
				; (will be cdrcache.sys path itself)

clnextword:
	mov ax,[es:bx+1]	; is it X:\...?
	cmp ax,':\'		; ignore those
	jz near clignored2
	mov ax,[es:bx]
	inc bx			; parse on... (skip " " etc.)
	cmp al,9		; tab? then skip.
	jz clnextword
	cmp al,13		; eof? (CR, LF, or 0)
	jbe clhelp		; too few arguments!

	cmp al,' '	; space?
	jz clnextword	; skip over space

	cmp ax,'/?'	; "/?" help request? (must have the / now!)
	jz clhelp

	; *** if no /?, it is the 1st real argument

%if SYNDEBUG
	mov byte [cs:synerr],'A'
%endif
	jmp short clgetfirstname

; --------------

clhelp:	mov si,clhelpmsg
		call strtty	; show help message (trashes AX BX SI)
	pop si
	pop eax
	pop bx
	pop es
	stc			; errors found
	ret

; --------------

clignored2:
	add bx,3	; skip "X:\"
clignore_initial:			; ***
%if SYNDEBUG
	mov byte [cs:synerr],'0'	; 0 is "line ended after x:\"
%endif
clignored:
	mov al,[es:bx]
	cmp al,' '	; skip until whitespace hit
	jz clnextword	; continue with normal parsing
	cmp al,9	; tab?
	jz clnextword
	cmp al,13
	jbe clhelp	; if end of line, too few args!
	inc bx
	jmp clignored	; skip on

; --------------

clgetfirstname:
	mov si,clientname	; 1st arg is copied there
clgfnl:	mov [cs:si],al		;store 1 char
	mov al,[es:bx]		; get next char
	inc bx			; sic!
	inc si			; sic!
	cmp al,' '		; space or eof?
	jbe clgetsecondname
	cmp si,clientname+8
	jz clhelp		; user tried to tell us a 9th char
	jmp short clgfnl

; -------------

clgetsecondname:
%if SYNDEBUG
	mov byte [cs:synerr],'a'
%endif
	cmp al,9		; tab?
	jz clgsnSpace
	cmp al,' '		; space or eof?
	jb clhelp		; eof: user did not tell us 2nd arg
	jnz clgsn		; no space: found 2nd arg
clgsnSpace:
	mov al,[es:bx]
	inc bx			; skip whitespace
	jmp short clgetsecondname

; -------------

clgsn:	mov si,nam		; 2st arg is copied here
%if SYNDEBUG
	mov byte [cs:synerr],'B'
%endif
clgsnl:	mov [cs:si],al		; store 1 char
	mov al,[es:bx]		; get next char
	inc bx			; sic!
	inc si			; sic!
	cmp al,' '		; space or eof?
	jbe clgotsecondname
	cmp si,nam+8
	jz clhelp		; user tried to tell us a 9th char
	jmp short clgsnl

; -------------

clgotsecondname:
%if SYNDEBUG
	mov byte [cs:synerr],'C'
%endif
	mov al,' '		; pad with spaces
	cmp si,nam+8
	jz clwrotesecondname
	mov [cs:si],al		; pad this (RBIL says we have to)
	inc si			; sic!
	jmp short clgotsecondname

; -------------

clwrotesecondname:
	mov al,[es:bx]
	cmp al,9		; tab?
	jz clgdigitsSpace
	cmp al,' '		; space or eof?
	jb clhelp_jump		; eof: user did not tell us 3rd arg
	jnz cldigits		; no space: found 3rd arg
clgdigitsSpace:	
	inc bx			; skip whitespace
	jmp short clwrotesecondname

; --------------

cldigits:		; VERY simple argument: factor 1..99 for
			; 1..99 * *128* sectors buffer
%if SYNDEBUG
	mov byte [cs:synerr],'#'
%endif
	mov ax,[es:bx]
	cmp al,'0'
	jb clhelp_jump	; not even a first digit? error!
	cmp al,'9'
	ja clhelp_jump	; not even a first digit? error!
	cmp ah,'0'
	jb singledigit	; no 2nd digit found
	cmp ah,'9'
	jbe twodigits	; 2nd digit found
singledigit:
	mov ah,al	; make the only digit the least significant one
	mov al,'0'	; add "2nd" digit more significant if none found
twodigits:
	sub ax,'00'
	jz clhelp_jump	; value 0 is not allowed!
	xchg al,ah	; low byte is first, more significant digit!
	aad 10		; AAD: ah = 0, al = ah*10 + al
	mov ah,0
	shl ax,7	; *** factor is *128*
	mov [cs:sectors],ax	; write the selected cache size

	; ignore all following text (can be used for comments)

; --------------

	pop si
	pop eax
	pop bx
	pop es
	clc		; no errors found
	ret

clhelp_jump:		; keep jumps short
	jmp clhelp

clhelpmsg:
%if SYNDEBUG
	db "Syntax error type "
synerr	db "1 ",13,10
%endif
	db "Syntax: CDRCACHE cdromname cachename size [comments]",13,10
	db 13,10
	db "  cdromname Device name, used to find the CD-ROM driver",13,10
	db "  cachename Name that CDRCACHE should give itself. You can",13,10
	db "            then tell SHSUCDX/MSCDEX/... that name instead",13,10
	db "            of the name of the CD-ROM driver to use this cache.",13,10
	db "  size      The buffer size. Maximum value: 99. The unit of",13,10
	db "            size is 256 kilobytes (allocated in XMS).",13,10
	db "  comments  Everything after the 3rd argument is ignored, so",13,10
	db "            you can use the comment argument for comments.",13,10
	db 0

