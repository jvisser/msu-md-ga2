; Mega CD MMIO addresses used for communicating with msu-md driver on the mega cd (mode 1)
MSU_COMM_CMD        equ $a12010                 ; Comm command 0 (high byte)
MSU_COMM_ARG        equ $a12011                 ; Comm command 0 (low byte)
MSU_COMM_ARG32      equ $a12012                 ; Comm command 1/2
MSU_COMM_CMD_CK     equ $a1201f                 ; Comm command 7 (low byte)
MSU_COMM_STATUS     equ $a12020                 ; Comm status 0 (0-ready, 1-init, 2-cmd busy)

; msu-md commands
MSU_PLAY            equ $1100                   ; PLAY      decimal no. of track (1-99) playback will be stopped in the end of track
MSU_PLAY_LOOP       equ $1200                   ; PLAY LOOP decimal no. of track (1-99) playback will restart the track when end is reached
MSU_PAUSE           equ $1300                   ; PAUSE     vol fading time. 1/75 of sec. (75 equal to 1 sec) instant stop if 0 pause playback
MSU_RESUME          equ $1400                   ; RESUME    none. resume playback
MSU_VOL             equ $1500                   ; VOL       volume 0-255. set cdda volume
MSU_NOSEEK          equ $1600                   ; NOSEEK    0-on(default state), 1-off(no seek delays)  seek time emulation switch
MSU_PLAYOF          equ $1a00                   ; PLAYOF    #1 = decimal no. of track (1-99) #2 = offset in sectors from the start of the track to apply when looping play cdda track and loop from specified sector offset

YM2612_ADDR_2       equ $a04002
YM2612_VALUE_2      equ $a04003

; Where to put the code
ROM_END             equ $80000

; MACROS: ------------------------------------------------------------------------------------------

    macro MSU_WAIT
.\@
        tst.b   MSU_COMM_STATUS
        bne.s   .\@
    endm

    macro MSU_COMMAND cmd, param
        MSU_WAIT
        move.w  #(\1|\2),MSU_COMM_CMD           ; Send msu cmd
        addq.b  #1,MSU_COMM_CMD_CK              ; Increment command clock
    endm

; MEGA DRIVE OVERRIDES : ------------------------------------------------------------------------------------------

        ; M68000 Reset vector
        org     $4
        dc.l    ENTRY_POINT                     ; Custom entry point for redirecting

        org     $72b80                          ; Original ENTRY POINT
Game

        org     $76582
        jmp     pause_on

        org     $765cc      ; Hooks after z80 bus request so we can update YM2612 registers. Actual base address = $765bc.
        jmp     pause_off

        org     $766f4
        jmp     play_music_track

        org     $76c10
        jmp     stop_sound

        org     $76b14
        jmp     fade_out


; MSU-MD Init: -------------------------------------------------------------------------------------

        org     ROM_END
ENTRY_POINT
        bsr.s   audio_init
        jmp     Game

audio_init
        jsr     msu_driver_init
        tst.b   d0                              ; if 1: no CD Hardware found
.audio_init_fail
        bne.s   .audio_init_fail                ; Loop forever

        MSU_COMMAND MSU_NOSEEK, 1
        MSU_COMMAND MSU_VOL,    255
        rts

; Sound: -------------------------------------------------------------------------------------

pause_on
    MSU_COMMAND MSU_PAUSE, 0

    ; Run original code
    moveq   #2,d2
    move.b  #$b4,d0
    jmp     $76588


pause_off
    MSU_COMMAND MSU_RESUME, 0

    ; Workaround for failing sample playback after resume
    ; Enable left/right audio for fm channel 6 (DAC)
    move.b  #$b6,YM2612_ADDR_2      ; Select channel 6 stereo control
    move.b  #$c0,YM2612_VALUE_2     ; Enable left/right audio

    ; Run original code
    btst    #7,(a5)
    bne     .fall_through
    jmp     $765e4
.fall_through
    jmp     $765d2


play_music_track
        MSU_WAIT

        movem.l  d7/a0,-(sp)
        sub.b   #$81,d7
        ext.w   d7
        add.w   d7,d7
        lea     AUDIO_TBL,a0
        move.w  (a0,d7),MSU_COMM_CMD            ; Send msu cmd
        addq.b  #1,MSU_COMM_CMD_CK              ; Increment command clock
        movem.l  (sp)+,d7/a0
        rts


stop_sound
        MSU_COMMAND MSU_PAUSE, 0

        ; Run original code
        moveq   #$2b,d0
        move.b  #$80,d1
        jmp     $76c16


fade_out
       MSU_COMMAND MSU_PAUSE, 75              ; Seems to be like a 3s fadeout in the original game which in practice is way too long. Make it 1s.

       ; Explicitly do not run original code!
       ; Fade out expires only after the next song has already started and then calls stop_sound.
       ; Does not happen in the original game because the original play_music_track code resets all 68k sound RAM area (fadeout timer included)
       rts


; TABLES: ------------------------------------------------------------------------------------------

        align 2
AUDIO_TBL                                   ; #Track Name
        dc.w    MSU_PLAY_LOOP|02            ; 02 - Ravaged Village
        dc.w    MSU_PLAY_LOOP|01            ; 01 - Title Theme
        dc.w    MSU_PLAY_LOOP|04            ; 04 - Boss Theme 1
        dc.w    MSU_PLAY_LOOP|12            ; 12 - Castle
        dc.w    MSU_PLAY_LOOP|10            ; 10 - Boss Theme 2
        dc.w    MSU_PLAY_LOOP|07            ; 07 - Ruins
        dc.w    MSU_PLAY_LOOP|08            ; 08 - Tower
        dc.w    MSU_PLAY_LOOP|15            ; 15 - Credits
        dc.w    MSU_PLAY_LOOP|09            ; 09 - Dragon's Throat Cave
        dc.w    MSU_PLAY_LOOP|11            ; 11 - Castle Gates
        dc.w    MSU_PLAY_LOOP|13            ; 13 - Dark Guld's Chamber
        dc.w    MSU_PLAY|14                 ; 14 - Ending
        dc.w    MSU_PLAY|16                 ; 16 - Final Score
        dc.w    MSU_PLAY|03                 ; 03 - Game Over
        dc.w    MSU_PLAY_LOOP|06            ; 06 - Intermission
        dc.w    MSU_PLAY_LOOP|05            ; 05 - Bonus Stage

; MSU-MD DRIVER: -----------------------------------------------------------------------------------

        align 2
msu_driver_init
        incbin  "msu-drv.bin"
