INCLUDE "hardware.inc"
INCLUDE "rand.asm"

SECTION "Header", ROM0[$100]
    jp EntryPoint
    ds $150 - @, 0; Make room for the header

EntryPoint:
    ; Do not turn the LCD off outside of VBlank
WaitVBlank:
    ld a, [rLY]
    cp 144
    jp c, WaitVBlank

    ; Turn the LCD off
    ld a, 0
    ld [rLCDC], a

    ; Copy the tile data
    ld de, Tiles
    ld hl, $9000
    ld bc, TilesEnd - Tiles
    call Memcopy

    ; Copy the tilemap
    ld de, Tilemap
    ld hl, $9800
    ld bc, TilemapEnd - Tilemap
    call Memcopy

    ; Copy the tile data
    ld de, Paddle
    ld hl, $8000
    ld bc, PaddleEnd - Paddle
    call Memcopy

    ld a, 0
    ld b, 160
    ld hl, _OAMRAM
ClearOam:
    ld [hli], a
    dec b
    jp nz, ClearOam

    ld hl, _OAMRAM
    ld a, 128 + 16
    ld [hli], a
    ld a, 16 + 8
    ld [hli], a
    ld a, 0
    ld [hli], a
    ld [hl], a

    ; Turn the LCD on
    ld a, LCDCF_ON | LCDCF_BGON | LCDCF_OBJON
    ld [rLCDC], a

    ; During the first (blank) frame, initialize display registers
    ld a, %11100100
    ld [rBGP], a
    ld a, %11100100
    ld [rOBP0], a

    ld a, 0
    ld [wFrameCounter], a

    ; Initialize world scroll data 
    ld a, 2
    ld [wScrollSpeedY], a
    ld a, 0
    ld [wTotalDepth], a

    ld a, 0
    ld [wRandIndex], a

    ld a, $FF
    ld [wGeneratedOffsetY], a

    ld hl, 0
    call WriteTotalDepth

    ld a, 0
    ld [wVelocityY], a

Main:
    ; Wait until it's *not* VBlank
    ld a, [rLY]
    cp 144
    jp nc, Main
WaitVBlank2:
    ld a, [rLY]
    cp 144
    jp c, WaitVBlank2

    ; Write to next row VRAM given our current scroll
    ld hl, $9800

    ld a, [rSCY] ; find the number of rows to seek to, divide rSCY by 8
    srl a ; a / 2
    srl a ; a / 4
    srl a ; a / 8

    ; don't draw if we've already 
    ld b, a ; stash a (row to seek to)
    ld a, [wGeneratedOffsetY]
    cp b
    jp z, DrawNextTileLineEnd
    ld a, b ; unstash a and cache it so we don't draw it next frame
    ld [wGeneratedOffsetY], a

    add a, SCRN_Y_B ; scroll to the bottom
    cp SCRN_VY_B ; check if we need to wrap scroll, we cannot be more than 32 rows down from the top
    jr c, SeekToTileMapRow
    sub SCRN_VY_B; wrap back to begin at a = 0/hl = $9800

    cp 0 ; if a == 0, just fill the first line (hl = $9800), no need to seek, we'll just underflow!
    jp z, DrawNextTileLine

SeekToTileMapRow: ; a contains the number of rows we need to skip past $9800
    ld bc, SCRN_VX_B ; skip the number of virtual tiles in the tilemap
    add hl, bc ; hl is now pointing to the next row of tilemap we need to write to
    dec a
    cp 0
    jp nz, SeekToTileMapRow

DrawNextTileLine:
    ; there are 20 tiles per line
    ld a, $A
    push hl
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a
    ld [hli], a

    ; increment total depth
    call LoadTotalDepth

    ld a, 1 ; increase depth by 1 each time we draw a tile
    ld bc, 0
    ld c, a
    add hl, bc

    call WriteTotalDepth

    ; if total depth is a multiple of 4, then draw a bubble sprite, otherwise the ocean is too dense with bubbles
    ld a, l
    and a, %00000011 ; Mask out all but the two least significant bits
    pop hl
    jr nz, DrawNextTileLineEnd ; draw bubble if depth is divisible by 4

    push hl
    call Random
    pop hl
    and $0F ; make sure a is not over 16/0x14
    add $02 ; offset so we're in the center 16 pixels
    ld bc, 0
    ld c, a
    add hl, bc
    ld [hl], $B

DrawNextTileLineEnd:

    ; Increment the Y-scroll register to scroll the background down
    ld a, [wScrollSpeedY]
    ld b, a
    ld a, [rSCY]
    add a, b
    ld [rSCY], a

    ; Check the current keys every frame and move left or right.
    call UpdateKeys

    call UpdatePhysix

    ; First, check if the left button is pressed.
CheckLeft:
    ld a, [wCurKeys]
    and a, PADF_LEFT
    jp z, CheckRight

Left:
    ; Move the paddle one pixel to the left.
    ld a, [_OAMRAM + 1]
    dec a
    dec a
    ; If we've already hit the edge of the playfield, don't move.
    cp a, 15
    jp z, Main
    ld [_OAMRAM + 1], a
    jp Main

; Then check the right button.
CheckRight:
    ld a, [wCurKeys]
    and a, PADF_RIGHT
    jp z, Main
Right:
    ; Move the paddle one pixel to the right.
    ld a, [_OAMRAM + 1]
    inc a
    inc a
    ; If we've already hit the edge of the playfield, don't move.
    cp a, 105
    jp z, Main
    ld [_OAMRAM + 1], a
    jp Main

; Copy bytes from one area to another.
; @param de: Source
; @param hl: Destination
; @param bc: Length
Memcopy:
    ld a, [de]
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or a, c
    jp nz, Memcopy
    ret

; Generates an 8 bit PRN in register A
Random:
    ; load rand index into a
    ld hl, wRandIndex
    ld a, [hl]

    ; Check if index is at the end of the buffer
    cp $FF ; The buffer has 256 values, final value is ignored
    jr c, .increment

    ; If at the end, reset the index
    xor a
    ld [hl], a

.increment
    inc a
    ld [hl], a

    ; index into address within RandomBuffer
    ld hl, RandomBuffer
    ld bc, 0
    ld c, a ; we can't ld a into bc directly, so have to initialize it by component
    add hl, bc

    ; Load the value from RandomBuffer into the a register
    ld a, [hl]

    ; XOR with the value in the divider register
    ld hl, rDIV
    ld b, [hl]
    xor b

    ret

UpdateKeys:
    ; Poll half the controller
    ld a, P1F_GET_BTN
    call .onenibble
    ld b, a ; B7-4 = 1; B3-0 = unpressed buttons

    ; Poll the other half
    ld a, P1F_GET_DPAD
    call .onenibble
    swap a ; A3-0 = unpressed directions; A7-4 = 1
    xor a, b ; A = pressed buttons + directions
    ld b, a ; B = pressed buttons + directions

    ; And release the controller
    ld a, P1F_GET_NONE
    ldh [rP1], a

    ; Combine with previous wCurKeys to make wNewKeys
    ld a, [wCurKeys]
    xor a, b ; A = keys that changed state
    and a, b ; A = keys that changed to pressed
    ld [wNewKeys], a
    ld a, b
    ld [wCurKeys], a
    ret

.onenibble
    ldh [rP1], a ; switch the key matrix
    call .knownret ; burn 10 cycles calling a known ret
    ldh a, [rP1] ; ignore value while waiting for the key matrix to settle
    ldh a, [rP1]
    ldh a, [rP1] ; this read counts
    or a, $F0 ; A7-4 = 1; A3-0 = unpressed keys
.knownret
    ret


UpdatePhysix:
    DEF BUOYANCY EQU 1
    ld a, [_OAMRAM] ; bouyant forces forces you to go up
    sub BUOYANCY
    ld [_OAMRAM], a

    ; ld a, [wVelocityY]
    ; add GRAVITY
    ; ld [wVelocityY], a
    ret


LoadTotalDepth:
    ld hl, wTotalDepth ; Load wTotalDepth into hl
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ret

WriteTotalDepth:
    ld a, l
    ld [wTotalDepth], a
    ld a, h
    ld [wTotalDepth+1], a
    ret

Tiles:
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33322222
	dw `33322222
	dw `33322222
	dw `33322211
	dw `33322211
	dw `33333333
	dw `33333333
	dw `33333333
	dw `22222222
	dw `22222222
	dw `22222222
	dw `11111111
	dw `11111111
	dw `33333333
	dw `33333333
	dw `33333333
	dw `22222333
	dw `22222333
	dw `22222333
	dw `11222333
	dw `11222333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33322211
	dw `33322211
	dw `33322211
	dw `33322211
	dw `33322211
	dw `33322211
	dw `33322211
	dw `33322211
	dw `22222222
	dw `20000000
	dw `20111111
	dw `20111111
	dw `20111111
	dw `20111111
	dw `22222222
	dw `33333333
	dw `22222223
	dw `00000023
	dw `11111123
	dw `11111123
	dw `11111123
	dw `11111123
	dw `22222223
	dw `33333333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `11222333
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `11001100
	dw `11111111
	dw `11111111
	dw `21212121
	dw `22222222
	dw `22322232
	dw `23232323
	dw `33333333
    ; ocean tile $A
	dw `22222222
	dw `22222222
	dw `22222222
	dw `22222222
	dw `22222222
	dw `22222222
	dw `22222222
	dw `22222222
    ; bubble tile $B
    dw `00000000
    dw `00033000
    dw `00322300
    dw `03222230
    dw `03222230
    dw `00322300
    dw `00033000
    dw `00000000
	; Paste your logo here:
TilesEnd:

Paddle:
    dw `13333331
    dw `30000003
    dw `13333331
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
    dw `00000000
PaddleEnd:

Tilemap:
	db $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $02, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $05, $06, $05, $06, $05, $06, $05, $06, $05, $06, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0A, $0B, $0C, $0D, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $0E, $0F, $10, $11, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $12, $13, $14, $15, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $07, $03, $16, $17, $18, $19, $03, 0,0,0,0,0,0,0,0,0,0,0,0
	db $04, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $09, $07, $03, $03, $03, $03, $03, $03, 0,0,0,0,0,0,0,0,0,0,0,0
TilemapEnd:

RandomBuffer:
    db $6F, $91, $8F, $5C, $5F, $E5, $C3, $1B, $19, $AB, $65, $6B, $25, $76, $8C, $12
    db $DB, $A4, $0A, $CC, $4D, $D9, $BF, $4F, $63, $3D, $8A, $72, $DD, $C6, $D3, $E1
    db $56, $E9, $06, $7A, $5A, $93, $BA, $C2, $45, $5E, $7D, $61, $5D, $31, $AF, $DF
    db $00, $30, $38, $3E, $2C, $47, $FF, $EB, $24, $A2, $46, $9D, $0C, $66, $E8, $C4
    db $79, $C1, $A0, $FB, $1A, $95, $77, $48, $ED, $B4, $67, $F9, $11, $54, $D8, $D1
    db $D5, $F2, $55, $34, $4E, $7E, $9A, $D4, $29, $5B, $20, $8D, $3F, $71, $1D, $81
    db $3B, $88, $08, $CE, $78, $10, $7F, $04, $73, $53, $B5, $75, $EC, $D2, $9C, $A6
    db $39, $6A, $0B, $9E, $05, $28, $0F, $B8, $83, $99, $6C, $9B, $B6, $3C, $B0, $82
    db $CB, $90, $86, $D0, $E6, $74, $A5, $94, $BE, $A9, $57, $C0, $62, $FD, $2F, $22
    db $13, $B7, $07, $59, $32, $BC, $C9, $F8, $09, $3A, $F0, $87, $4C, $6D, $49, $23
    db $A3, $B1, $8B, $CF, $DA, $AE, $FA, $1C, $8E, $1F, $0E, $F1, $17, $E7, $AA, $41
    db $4B, $70, $FC, $01, $EF, $03, $43, $18, $E2, $37, $42, $C8, $9F, $A8, $33, $96
    db $0D, $E4, $27, $35, $7C, $16, $7B, $A7, $DE, $CA, $44, $80, $2A, $15, $F3, $14
    db $F7, $C7, $AC, $E0, $2B, $51, $2E, $89, $50, $BD, $F6, $2D, $D7, $DC, $98, $AD
    db $6E, $E3, $52, $92, $36, $40, $B9, $BB, $B2, $26, $C5, $02, $84, $64, $F4, $EE
    db $F5, $97, $58, $85, $4A, $B3, $EA, $A1, $CD, $D6, $FE, $1E, $69, $68, $21, $60
RandomBufferEnd:

SECTION "Counter", WRAM0
wFrameCounter: db

SECTION "Input Variables", WRAM0
wCurKeys: db
wNewKeys: db

SECTION "Dan", WRAM0
wVelocityY: db

SECTION "Scrolling and Worldgen", WRAM0
wScrollSpeedY: db
wGeneratedOffsetY: db
wTotalDepth: dw
wCurrentDepth: dw ; unused

SECTION "Random", WRAM0
wRandIndex: db
