; Seven Kingdoms: Ancient Adversaries
;
; Copyright 1997,1998 Enlight Software Ltd.
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;

;Filename    : IB_ATDM.ASM
;Description : Blt a bitmap to the display surface buffer
;	       with decompression, transparency handling
;              and horizontal mirroring


INCLUDE IMGFUN.inc
INCLUDE COLCODE.inc

.CODE


;----------- BEGIN OF FUNCTION IMGbltAreaTransDecompressHMirror ------
;
; Put a compressed bitmap on image buffer.
; It does handle color key transparency.
;
; Syntax : IMGbltAreaTransDecompress( imageBuf, pitch, x, y, bitmapBuf,
;                 x1, y1, x2, y2)
;
; char *imageBuf - the pointer to the display surface buffer
; int  pitch        - pitch of the display surface buffer
; int  x,y       - where to put the image on the surface buffer
; char *bitmapPtr  - the pointer to the bitmap buffer
; int  x1,y1,x2,y2 - clipping window from left, top of the bitmap
;
; the area to be blit to the screen is called clip window
; the width of clip window is stored in clipWindow
;
; ESI and AH points to a point in the bitmap data
; if ESI points to a compression key (i.e. F8-FF),
; AH refer to how many of points are passed.
; i.e. [esi] = F8 21, AH may to 0 to 20
;
; SeekForward function move the (ESI,AH) pointer
; to forward ECX points (decompressed)
;
; ESI and AH are positioned to the top right hand corner of clip window
; and move left, and then downward
; (EDI is increasing and EDI is decreasing on a line)
;
; After the cursor moved right, it checks for three cases:
; 1. non-transparent data
; 2. transparent data, but do not pass the left of the clip window
; 3. transparent data, and will pass the left of the clip window
;
; for case 1, blit the point and move one point left. If the left
; side of the clip window is passed, position EDI and (ESI,AH) to the
; right side of the clip window on next line.
;
; for case 2, simply move the EDI backward and (ESI,AH) forward by the
; run-length count
;
; for case 3, skip EDI and (ESI,AH) to the right side of the clip window
; on the next line
;
;
;-------------------------------------------------
;
; Format of the bitmap data :
;
; <short>  width
; <short>  height
; <char..> bitmap image
;
;-------------------------------------------------

		PUBLIC	IMGbltAreaTransDecompressHMirror
SeekForward	PROTO	STDCALL			; see IB_ATRD.ASM

IMGbltAreaTransDecompressHMirror PROC imageBuf,pitch,x,y,bitmapPtr,x1,y1,x2,y2
		LOCAL	clipWidth:DWORD, bitmapWidth:DWORD, bitmapHeight:DWORD
		LOCAL	tempESI:DWORD
		STARTPROC

		MOV	EAX, imageBuf		; store the address of the image buffer to a variable
		MOV	image_buf, EAX

		;------ get the bitmap width and height -----;

		MOV     AX , DS
		MOV	ES , AX
		MOV     ESI, bitmapPtr

		;------ calculate destination on the video memory ----;
		;------ draw from top right hand corner
		CALC_ADDR_2 EDI, x, y, x2, y1,pitch     ; Get the address to the destination buffer

		;------ calculate clipWidth - no. of points ploted on each row --;
		XOR	EAX, EAX
		LODSW                            ; get bitmap width
		MOV     bitmapWidth, EAX
		MOV	EAX, x2
		SUB	EAX, x1
		INC	EAX
		MOV     clipWidth, EAX

		;----- calculate number of rows to be ploted on the screen
		LODSW                            ; get bitmap height
		MOV	bitmapHeight, EAX
		MOV     ECX, EAX
		MOV	ECX, y2
		SUB	ECX, y1
		; INC	ECX			; leave last line less to @@last_line
		; last line is handled separately to avoid seekForward

		JC	@@end			; if negative, skip the procedure

		; ----- position ESI to the first point to draw -------
		; AH contain the bytes remained in decompression
		; position to row y1 and column x2
		PUSH	ECX
		; ECX = (y1 +1) * bitmapWidth - x2 -1
		MOV	EAX, y1
		INC	EAX
		MUL	bitmapWidth
		SUB	EAX, x2		; DROP EDX
		DEC	EAX
		MOV	ECX, EAX
		MOV	AH,0
		CALL	SeekForward

		POP	ECX		; ECX is now the height of clipping window

		JECXZ	@@lastLine
@@loopY:	;---------- start of each line ------------
		PUSH	ECX

		MOV	ECX, clipWidth
@@loopX:
		; --------- start of each point -----------
		LODSB
		JUMP_IF_TRANS al, @@clipCompress1
@@nonTrans:
		; ------- non-transparent data -----------
		; 00-F7, simply blit the point on video memory
		; ES:
		MOV	[EDI], AL
		DEC	EDI

		; -------- test end of line
		;  (pass the right of clipping window)
		LOOP	@@loopX
		ADD	EDI, pitch
		ADD	EDI, clipWidth

		; -------- seek source(ESI) to next line -----
		MOV	ECX, bitmapWidth
		SUB	ECX, clipWidth
		MOV	AH,0
		CALL	SeekForward
		JMP	@@endloopY

		ALIGN	4
@@clipCompress1:
		; ------ transparent data -------------
		MOV	tempESI, ESI		; save ESI
		; note: run-length is now in [ESI]-AH
		JUMP_IF_NOT_MANY_TRANS al, @@clipCompress1a
		LODSB				; load the run-length count
		ENCODE_FEW_TRANS_CODE al
@@clipCompress1a:
		MOV	DL,AL
		DECODE_FEW_TRANS_CODE dl
		SUB	DL,AH
		MOVZX	DX,DL

		CMP	ECX, EDX
		JBE	@@clipCompress2

		; ECX > EDX
		; meaning the run-length is still within clip window
		SUB	EDI, EDX	; skip the number of points
		SUB	ECX, EDX
		MOV	AH,0
		JMP	@@loopX

		ALIGN	4
@@clipCompress2:
		; --------  run-length is outside clip window --------
		; EDI seek the the start of the next line
		; EDI += ECX - clipWidth + pitch
		ADD	EDI, pitch
		SUB	ECX, clipWidth
		SUB	EDI, ECX
		; find out the no. of byte to call SeekForward
		; to seek the left side of clip window of next line
		; ECX = (ECX - clipWidth) + bitmapWidth
		ADD	ECX, bitmapWidth
		MOV	ESI, tempESI	; restore ESI to compresion key (f8-ff)
		DEC	ESI
		CALL    SeekForward

@@endloopY:	POP	ECX
		LOOP    @@loopY

		;------- similarly blit the last line -------;

@@lastLine:
		MOV	ECX, clipWidth
@@lastLoopX:
		LODSB
		JUMP_IF_TRANS al, @@lastClipCompress1
@@lastNonTrans:
		; ES:
		MOV	[EDI], AL
		DEC	EDI

		; --------- test end of line ----------
		LOOP	@@lastLoopX
		JMP	@@endLast

		ALIGN	4
@@lastClipCompress1:
		; note: run-length is now in AH not [ESI]
		JUMP_IF_NOT_TRANS al, @@lastClipCompress1a
		; F8
		LODSB
		ENCODE_FEW_TRANS_CODE al
@@lastClipCompress1a:
		MOV	DL,AL
		DECODE_FEW_TRANS_CODE dl
		SUB	DL,AH
		MOVZX	DX,DL

		CMP	ECX, EDX
		JBE	@@endLast
		; ECX > EDX
		; meaning the run-length is still within clip window
		SUB	EDI, EDX	; skip the number of points
		SUB	ECX, EDX
		MOV	AH,0

		JMP	@@lastLoopX
		ALIGN	4
@@endLast:

@@end:          ENDPROC
IMGbltAreaTransDecompressHMirror	ENDP

;----------- END OF FUNCTION IMGbltAreaTransDecompressHMirror ----

END
