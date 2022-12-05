COMMENT *

SOFTHDDI.ASM
Software Hard Disk Drive Indicators -- Jim Leonard, 2022

Provides simulated hard disk activity "LED"s and seeking sounds.
Intended for DOS systems with solid-state hard drives that lack both,
so that disk activity can again be seen/heard.

Three hard disk "indicators" are available, and can be enabled in any
combination:
  - An on-screen "LED" that appears in the upper left corner
  - An audible "click" that simulates HDD head seek noise
  - On AT+ systems, the keyboard CAPSLOCK/NUMLOCK/SCROLLLOCK indicator LEDs

Run "SOFTHDDI" with no arguments to see command-line usage.

IMPACT:

The TSR uses roughly 1KB of RAM when resident, and automatically loads
itself into upper memory blocks if present.

The on-screen "LED" and speaker click indicators are effectively free, but
the keyboard LEDs indicator can result in a slowdown (see LIMITATIONS below).

IMPLEMENTATION NOTES

Painting the "virtual LED" on-screen is handled differently based on
what video mode the system is currently in.  The goal is to display a
flashing square in the upper left corner whenever there is disk
activity.  The basic ideas:

- Color and B&W text modes:  Colors are changed to become lightred-on-red.

- Mono text mode:  Colors are changed to become darkgreen-on-green.
On some monitors this attribute can result in a "halo", enhancing the effect.

- Graphics modes (fixed palettes):  An 8x8-pixel "LED" graphic is painted.

- Graphics modes (redefinable palettes):  An 8x8 square area is created
by flipping all bits in that area.  This method was chosen to have the
least impact to the system while still having a high likelyhood of
visibility no matter what the color palette is set to.

LIMITATIONS

On-screen "LED":

- Video modes above 13h (ie. SVGA/VESA) are ignored.  Supporting those
would take up too much resident RAM and CPU time.  Besides, if you can run
those modes, you have a fast system, and would likely never see the "LED"
in practice anyway.  Other indicators (sound, kbd LEDs) work fine in SVGA.

- Not all video modes below 13h are supported; more support will be added
as time permits.

- Unchained VGA modes are not yet detected and handled correctly, which
results in some (harmless) graphical corruption in the upper right corner.

Keyboard LEDs:

- Enabling the keyboard LEDs will result in a loss of I/O performance.
This is due to the amount of hardware reads and writes necessary to interact
with the keyboard controller safely.

- If the keyboard controller is busy when this program needs to flash the
LEDs, the LEDs may temporarily stop illuminating.  If this happens, hit
numlock, capslock, or scrollock to return LEDs to normal.

Speaker clicks:

- The volume of the speaker click is fixed and cannot be made louder/softer.
Volume level was made as loud as possible with minimal impact to the system.

- If playing digitized audio through the PC speaker, such as in RealSound
games, the speaker click may stop working.  Make any normal sound through
the speaker to return functionality.  (One quick way is to type CTRL-G at
the DOS prompt.)

FUTURE IMPROVEMENTS

- Add support for missing modes < 13h (Hercules graphics, Tandy, etc.)

- Explore potential size/speed improvements, such as only installing and
calling the exact code paths needed

ACKNOWLEDGEMENTS

This TSR relies on the Alternate Multiplex Interrupt Specification authored
by Ralf Brown for its terminate-and-stay-resident functionality.
AMIS-compliant TSRs have several advantages over typical TSRs, including:
  - Only resident code goes resident, resulting in smaller RAM usage
  - Can automatically load themselves to upper ram if UMBs are available
  - Can load and unload TSRs in any order
The AMIS specification, and code portions used here, are (C) Ralf Brown.
For a description of AMIS and an example AMIS library, consult AMISL092.ZIP.

Information on programming the keyboard LEDs courtesy of Frank van Gilluwe.
Information on determining PC vs. AT 8255 from Kris Heidenstrom (RIP).
Methodology for detecting video hardware adapted from Richard Wilton.

Greetz to VileR, who drew a CGA mode4+mode6 "LED" bitmap on short notice :-)

*

        .8086
        LOCALS          ;Enable local symbols within each PROC
        INCLUDE AMIS.MAC

        @Startup 2,00   ;need DOS 2.00
                        ;this macro also takes care of declaring
                        ;segments in the required order

VERSION_NUM equ 0011h   ;v1.1
VERSION_STR equ "1.1"

; Program behaviors that can be tuned by changing vars and re-assembling:
; (It isn't necessary to change these in most cases)

REMOVESNOW EQU 1        ;Avoid CGA "snow" on original CGA cards.
                        ;0 = No snow avoidance
                        ;1 = Avoids snow at a slight speed penalty
                        ;Set to 0 if you never use a CGA card; saves ~60 bytes

SEEKSOUNDS EQU 1        ;Tries to make sounds only when there is head movement.
                        ;0 = Clicks on all calls; can generate random noise
                        ;1 = Only clicks when head moves (realistic)
                        ;Leave at 1 for more realistic-sounding behavior.

OMITFLOPPY EQU 1        ;Don't show activity for floppy drives.
                        ;0 = Show INT13 activity for floppy+hard drives
                        ;1 = Limit activity to hard disk drives
                        ;Leave at 1 unless your floppy/gotek lacks LEDs.

NOBIOSMODE EQU 0        ;Show LED in lower-right corner in non-BIOS CGA modes.
                        ;0 = Non-BIOS modes will not show an onscreen LED
                        ;1 = All modes will show LED, but with much CGA "snow"
                        ;Leave at 0 unless you *must* have an LED in games
                        ;that bypass the BIOS and also perform HDD activity.
                        ;(There are hardly any games that meet both criteria)

; Resident code goes into its own segment so that all the offsets are
; proper for the new location after copying it into a new location

TSRcode@
start_TSRcode label byte

; Declare the interrupt vector hooked by the program, then set up the
; Alternate Multiplex Interrupt Spec handler
;
        HOOKED_INTS 13h
        ALTMPX  'JLeonard','SOFTHDDI',VERSION_NUM,'Virtual HDD LED/sound indicators'

; Resident portion of interrupt handler follows:

;feature flags for visual indicators we can install:
fLED equ (1 SHL 0)              ;virtual on-screen LED
fSND equ (1 SHL 1)              ;speaker click
fKBD equ (1 SHL 2)              ;keyboard LED
fHED equ (1 SHL 3)              ;head moved, time to make noise

; 8253 commands:
iMC_BinaryMode          EQU 0
iMC_OpMode2             EQU 4   ;Rate generator
iMC_LatchCounter        EQU 0
iMC_Chan0               EQU 0

; Draw assumptions
LEDattrC                EQU 4Ch ;lightred on red
LEDattrM                EQU 78h ;dark green on green

; Video card hardware class -- used for catching modes not set by the BIOS
h_MDA   EQU 1
h_HGC   EQU h_MDA OR 80h
h_CGA   EQU 2
h_EGA   EQU 3
h_MCGA  EQU 4
h_VGA   EQU 5

curvidm db 0                    ;video mode active at time handler was invoked
vidcard db 0                    ;video card detected at startup, assume nothing
oldVRAM db (8*2) DUP (?)        ;Save VRAM we change (enough for CGA graphics)
oldVTXT db 2 DUP (?)            ;Same, but for text if we need to do T+G
oldSpkr db 0                    ;for restoring speaker state when click ends
spkrTic dw 1193                 ;# of ticks to fire speaker for 1ms
starTic dw 0                    ;starting tick counter value
i_flags db 0                    ;user-desired indicator flags
lastTrk dw 0                    ;last track we were on
spkrbit EQU 00000010b           ;bit that enables/disables current to speaker

;Video segment table
VIDSEGS dw 0b800h,\             ;00  40x25 B/W text
           0b800h,\             ;01  40x25 color text
           0b800h,\             ;02  80x25 shades of gray text
           0b800h,\             ;03  80x25 color text
           0b800h,\             ;04  320x200x4
           0b800h,\             ;05  320x200x4
           0b800h,\             ;06  640x200x2
           0b000h,\             ;07  80x25 Monochrome text
           0b800h,\             ;08  160x200x16 (Tandy/PCjr)
           0b800h,\             ;09  320x200x16 (Tandy/PCjr)
           0b800h,\             ;0A  640x200x4  (Tandy/PCjr)
           0b800h,\             ;0B  640x200x16 (Tandy SL/TL)
           0a000h,\             ;0C  Reserved   (EGA BIOS internal?)
           0a000h,\             ;0D  320x200x16
           0a000h,\             ;0E  640x200x16
           0a000h,\             ;0F  640x350 Monochrome graphics
           0a000h,\             ;10  640x350x16
           0a000h,\             ;11  640x480x2
           0a000h,\             ;12  640x480x16
           0a000h               ;13  320x200x256

;Draw routine jumptable
drawtbl dw OFFSET draw_40col,\  ;00  40x25 B/W text
           OFFSET draw_40col,\  ;01  40x25 color text
           OFFSET draw_80col,\  ;02  80x25 shades of gray text
           OFFSET draw_80col,\  ;03  80x25 color text
           OFFSET draw_mode4,\  ;04  320x200x4
           OFFSET draw_mode4,\  ;05  320x200x4
           OFFSET draw_mode4,\  ;06  640x200x2
           OFFSET draw_mono, \  ;07  80x25 Monochrome text
           OFFSET draw_null, \  ;08  160x200x16 (Tandy/PCjr)
           OFFSET draw_null, \  ;09  320x200x16 (Tandy/PCjr)
           OFFSET draw_null, \  ;0A  640x200x4  (Tandy/PCjr)
           OFFSET draw_null, \  ;0B  640x200x16 (Tandy SL/TL)
           OFFSET draw_null, \  ;0C  Reserved   (EGA BIOS internal?)
           OFFSET draw_null, \  ;0D  320x200x16
           OFFSET draw_null, \  ;0E  640x200x16
           OFFSET draw_null, \  ;0F  640x350 Monochrome graphics
           OFFSET draw_null, \  ;10  640x350x16
           OFFSET draw_null, \  ;11  640x480x2
           OFFSET draw_null, \  ;12  640x480x16
           OFFSET draw_mod13    ;13  320x200x256

;Erase routine jumptable
erastbl dw OFFSET eras_40col,\  ;00  40x25 B/W text
           OFFSET eras_40col,\  ;01  40x25 color text
           OFFSET eras_80col,\  ;02  80x25 shades of gray text
           OFFSET eras_80col,\  ;03  80x25 color text
           OFFSET eras_mode4,\  ;04  320x200x4
           OFFSET eras_mode4,\  ;05  320x200x4
           OFFSET eras_mode4,\  ;06  640x200x2
           OFFSET eras_mono, \  ;07  80x25 Monochrome text
           OFFSET eras_null, \  ;08  160x200x16 (Tandy/PCjr)
           OFFSET eras_null, \  ;09  320x200x16 (Tandy/PCjr)
           OFFSET eras_null, \  ;0A  640x200x4  (Tandy/PCjr)
           OFFSET eras_null, \  ;0B  640x200x16 (Tandy SL/TL)
           OFFSET eras_null, \  ;0C  Reserved   (EGA BIOS internal?)
           OFFSET eras_null, \  ;0D  320x200x16
           OFFSET eras_null, \  ;0E  640x200x16
           OFFSET eras_null, \  ;0F  640x350 Monochrome graphics
           OFFSET eras_null, \  ;10  640x350x16
           OFFSET eras_null, \  ;11  640x480x2
           OFFSET eras_null, \  ;12  640x480x16
           OFFSET eras_mod13    ;13  320x200x256

;INT 13 services jumptable:
;Decision table; only perform indicators for calls that generate activity
dsvctbl db 0, \ ;0  Reset disk system
           0, \ ;1  Get disk status
           1, \ ;2  Read disk sectors
           1, \ ;3  Write disk sectors
           1, \ ;4  Verify disk sectors
           1, \ ;5  Format disk track
           0, \ ;6  Format track and set bad sector flag
           0, \ ;7  Format the drive starting at track
           0, \ ;8  Get current drive parameters
           0, \ ;9  Initialize 2 fixed disk base tables
           1, \ ;A  Read long sector
           1, \ ;B  Write long sector
           1, \ ;C  Seek to cylinder
           0, \ ;D  Alternate disk reset
           0, \ ;E  Read sector buffer
           0    ;F  Write sector buffer

IODELAY macro
        jmp short $+2   ;force bus cycle by clearing prefetch queue
        jmp short $+2   ;again, in case the L1 cache invalidated the first one
endm

GET_TIMER_CHAN0 macro
        mov     al,iMC_Chan0 + iMC_LatchCounter + iMC_OpMode2 + iMC_BinaryMode
        out     43h,al                  ;latch counter value
        in      al,40h                  ;get LSB of timer counter
        mov     ah,al
        in      al,40h                  ;get MSB of timer counter
        xchg    al,ah                   ;ax = starting value
endm

WAITHRETRACE macro ;dx must be 03dah before calling
LOCAL   wait1,wait2,in_vert
wait1:
        in      al,dx                   ;grab status bits
        test    al,8                    ;are we in vertical retrace?
        jnz     in_vert                 ;if so, immediately exit
        shr     al,1                    ;are we already in random h. retrace?
        jc      wait1                   ;if so, keep waiting
wait2:
        in      al,dx                   ;grab status bits
        shr     al,1                    ;are we in horizontal retrace?
        jnc     wait2                   ;if not, keep waiting
in_vert:
endm


;----------------------------------------------------------------------------
; Indicator (speaker, on-screen "LED", keyboard LED) start procedures.
; These fire before the real INT 13h call executes.
diskIntEnter PROC
        push    ds
        push    ax

        push    cs
        pop     ds                      ;to make var/table addressing easier

        ;The speaker click needs time to be audible, so we start it first.
        ;This frees up the CPU to go run other code while the speaker cone
        ;travels toward the maximum +5v position.  We note the current 8253
        ;timer value, so that we can later measure if enough time has elapsed
        ;to produce a lound enough "click".

startSpeaker:
        test    [i_flags],fSND          ;did user want sound?
        jz      startLED                ;skip to virtual LED if not
        ;If we sound off for every call, even without head movement, speaker
        ;gets noisy!  We want to make noise only if the "heads" actually move.
        ;On entry, CX has track+sector values, so we'll use that.
        IF SEEKSOUNDS
        and     [i_flags],NOT fHED      ;clear "head moved" flag
        mov     ax,cx                   ;copy track+sector argument to ax
        and     al,11000000b            ;isolate track # in ax
        cmp     [lastTrk],ax            ;did track change? (sets flags)
        mov     [lastTrk],ax            ;(store track for next int13 call)
        je      startLED                ;if it didnt change, leave spkr alone
        ENDIF
        or      [i_flags],fHED          ;set "head moved" flag
        in      al,61h                  ;get existing 8255 spkr port settings
        mov     [oldSpkr],al            ;save them for restoring later
        or      al,spkrbit              ;set bit to force speaker on
        out     61h,al                  ;send current to speaker coil
        ;note current timer count for comparing later
        GET_TIMER_CHAN0
        mov     [starTic],ax            ;save for later comparisons

startLED:
        test    [i_flags],fLED          ;did user want virtual LED?
        jz      startKBD                ;skip if not
        push    es
        mov     ax,40h
        mov     es,ax                   ;es->BIOS Data Area
        mov     al,[es:49h]             ;40:49 -> what BIOS thinks vidmode is
        mov     [curvidm],al            ;store for when we exit the handler
        cmp     al,13h                  ;is our video mode unsupported?
        ja      invalidvideomode        ;bail if so, otherwise fall through
        push    bx
        xor     bx,bx
        mov     bl,al                   ;bx = video mode
        shl     bl,1                    ;bx = index into vseg and jump tables
        push    di
        xor     di,di                   ;draw LED at offset 0 (upper left)
        mov     es,[bx+VIDSEGS]         ;es = current active vidram segment
        call    [bx+drawtbl]            ;draw the virtual LED on-screen
        pop     di
        pop     bx
        pop     es

startKBD:
        test    [i_flags],fKBD          ;did user want keyboard LEDs?
        jz      stopSpeaker             ;skip if not
        push    dx
        mov     dl,7                    ;set all three LEDs to ON
        call    setKBDLEDs
        pop     dx

stopSpeaker:
        ;We're done with other indicators, so we check if enough time has
        ;elapsed for the click to be audible.  If not, we wait until it has.
        test    [i_flags],fHED          ;did we make sound?
        jz      doneEnterHandler        ;skip if not
        push    bx
clickwait:
        GET_TIMER_CHAN0
        mov     bx,[starTic]            ;copy original value to scratch
        sub     bx,ax                   ;subtract new value from old value
        cmp     bx,[spkrTic]            ;compare si to maximum time allowed
        jb      clickwait               ;keep waiting if min ticks not elapsed
        in      al,61h                  ;get existing 8255 spkr port settings
        and     al,NOT spkrbit          ;turn off current to speaker coil
        out     61h,al
        pop     bx

doneEnterHandler:
        pop     ax
        pop     ds
        ret

invalidvideomode:
        pop     es                      ;pop ES from beginning of startLED
        jmp     startKBD                ;continue with the handler
diskIntEnter ENDP


;----------------------------------------------------------------------------
;Set keyboard physical LEDs
;Input:         dl = LED bits to enable
;Trashes:       ax

setKBDLEDs PROC
        push    es
        mov     ax,40h
        mov     es,ax                   ;es->BIOS Data Area
        push    bx
        mov     bx,97h                  ;es:bx = 40h:97h = BDA keyboard flags
        pushf
        cli                             ;need no kbd ints while we're here
        test    byte ptr es:[bx],40h    ;already updating keyboard?
        jnz     setLED_return3          ;bail; we'll catch it on next run
        or      byte ptr es:[bx],40h    ;set update in-progress
        mov     al,0EDh                 ;EDh = Update LED command
        call    keyboard_write          ;send keyboard command
        test    byte ptr es:[bx],80h    ;error writing to keyboard?
        jnz     setLED_return1          ;exit and recover if so
        mov     al,dl
        and     al,7                    ;sending anything other than LEDs=hang
        call    keyboard_write          ;send keyboard data
        test    byte ptr es:[bx],80h    ;error writing to keyboard?
        jz      setLED_return2          ;jump if not
setLED_return1:
        mov     al,0F4h                 ;error occured; reset+enable keyboard
        call    keyboard_write          ;sent keyboard command
setLED_return2:
        and     byte ptr es:[bx],3Fh    ;Record no error in BDA flags
setLED_return3:
        popf                            ;done with keyboard hardware
        pop     bx
        pop     es
        ret
setKBDLEDs ENDP


;----------------------------------------------------------------------------
;keyboard_write proc for safely sending data to keyboard controller
;
;Send byte AL to the keyboard controller (port 60h).
;Assumes no BIOS interrupt 9 handler active.
;If the routine times out due to the buffer remaining full, ah is non-zero.
;
;Called with:   al = byte to send
;               ds = cs
;Returns:       ah = 0 if successful, ah = 1 if failed

keyboard_write PROC
        push    cx
        push    dx
        mov     dl,al                   ;save data for keyboard

        ;wait until "keyboard receive" timeout is clear (usually is)
        xor     cx,cx                   ;counter for timeout
kbd_wrt_loop1:
        in      al,64h                  ;get keyboard status
        IODELAY
        test    al,20h                  ;receive timeout occurred?
        jz      kbd_wrt_ok1             ;jump if not
        loop    kbd_wrt_loop1           ;try again
        mov     ah,1                    ;return as failed
        jmp     kbd_wrt_exit

kbd_wrt_ok1:
        in      al,60h                  ;dispose of anything in buffer

        ;wait for input buffer to clear (usually is)
        xor     cx,cx                   ;counter for timeout
kbd_wrt_loop:
        in      al,64h                  ;get keyboard status
        IODELAY
        test    al,2                    ;check if buffer in use
        jz      kbd_wrt_ok              ;jump if not in use
        loop    kbd_wrt_loop            ;try again
        mov     ah, 1                   ;still busy; return as failed
        jmp     kbd_wrt_exit

kbd_wrt_ok:
        mov     al,dl
        out     60h,al                  ;send data to controller/keyboard
        IODELAY

        ;wait until input buffer clear (usually is)
        xor     cx,cx                   ;counter for timeout
kbd_wrt_loop3:
        in      al,64h                  ;get keyboard status
        IODELAY
        test    al,2                    ;check if kbd buffer in use
        jz      kbd_wrt_ok3             ;jump if not in use
        loop    kbd_wrt_loop3
        mov     ah,1                    ;still in use; return as failed
        jmp     kbd_wrt_exit

        ; wait until output buffer clear
kbd_wrt_ok3:
        mov     ah,8                    ;larger delay loop (8 * 64K)
kbd_wrt_loop4:
        xor     cx,cx                   ;counter for timeout
kbd_wrt_loop5:
        in      al,64h                  ;get keyboard status
        IODELAY
        test    al,1                    ;check if buffer in use
        jnz     kbd_wrt_ok4             ;jump if not in use
        loop    kbd_wrt_loop5
        dec     ah
        jnz     kbd_wrt_loop4
kbd_wrt_ok4:
        xor     ah,ah                   ;return status ok

kbd_wrt_exit:
        pop     dx
        pop     cx
        ret
keyboard_write ENDP


;----------------------------------------------------------------------------
;Sub-handlers for supported video modes:
;
;All sub-handlers can assume:
;  DS = CS
;  ES = video ram segment on entry
;  DI = offset of "LED" in VRAM (ok to trash)
;  AX = video mode      (ok to trash)
;  BX = video mode * 2  (ok to trash)
;All draw sub-handlers save what they're touching, then draw virtual LED
;All erase sub-handlers restore what the draw routine touched




draw_80col PROC
IF NOBIOSMODE
        push    di
        mov     di,(80*(99-4))+78       ;LED in lower-left corner
        call    draw_mode4
        pop     di
ENDIF
        nop
        inc     di                      ;first char attribute is at offset 1
IF REMOVESNOW
        cmp     [vidcard],h_CGA         ;hold up, is this a real CGA card?
        jne     @@quickwrite            ;if not, just write the attributes
        push    dx
        mov     dx,3DAh
        ;save existing attributes without snow:
        push    ds
        push    si                      ;preserve ds:si for restoring later
        push    es
        pop     ds                      ;ds = es
        mov     si,di                   ;ds:si = VRAM
        WAITHRETRACE
        lodsb                           ;1st attr in al
        mov     bl,al
        inc     si                      ;point to next attr
        WAITHRETRACE
        lodsb                           ;2nd attr in al
        mov     bh,al                   ;1st in bl, 2nd in bh
        pop     si
        pop     ds                      ;ds back to data seg
        mov     [word ptr oldVTXT],bx   ;record saved attributes
        ;write new attributes without snow
        mov     bl,LEDattrC             ;get attribute ready
        WAITHRETRACE
        xchg    bx,ax
        stosb
        xchg    bx,ax                   ;prime next attribute write
        inc     di
        WAITHRETRACE
        xchg    bx,ax
        stosb
        pop     dx
        ret

@@quickwrite:
        mov     al,es:[di]              ;grab first attr
        mov     ah,es:[di+2]            ;grab second attr
        mov     [word ptr oldVTXT],ax   ;record saved attributes
        mov     al,LEDattrC             ;write out the two attributes
        stosb                           ;that will make up our on-screen "LED"
        inc     di
        stosb
        ret
ELSE
        mov     al,es:[di]              ;grab first attr
        mov     ah,es:[di+2]            ;grab second attr
        mov     [word ptr oldVTXT],ax   ;record saved attributes
        mov     al,LEDattrC             ;write out the two attributes
        stosb                           ;that will make up our on-screen "LED"
        inc     di
        stosb
        ret
ENDIF
draw_80col ENDP

eras_80col PROC
IF NOBIOSMODE
        push    di
        mov     di,(80*(99-4))+78       ;LED in lower-left corner
        call    eras_mode4
        pop     di
ENDIF
        nop
        inc     di                      ;first char attribute is at offset 1
        mov     ax,[word ptr oldVTXT]   ;retrieve what we need to restore
IF REMOVESNOW
        cmp     [vidcard],h_CGA         ;hold up, is this a real CGA card?
        jne     @@quickwrite            ;if not, just write the attributes
        push    dx
        mov     bx,ax                   ;prime values for later writing
        mov     dx,3DAh
        WAITHRETRACE
        xchg    bx,ax
        stosb
        inc     di
        mov     al,ah
        xchg    bx,ax
        WAITHRETRACE
        xchg    bx,ax
        stosb
        pop     dx
        ret

@@quickwrite:
        stosb                           ;restore 1st attr
        inc     di                      ;di already +1; make +2
        mov     al,ah                   ;retrieve second attribute
        stosb                           ;restore 2nd attr
        ret
ELSE
        stosb                           ;restore 1st attr
        inc     di                      ;di already +1; make +2
        mov     al,ah                   ;retrieve second attribute
        stosb                           ;restore 2nd attr
        ret
ENDIF
eras_80col ENDP

draw_mono PROC
        inc     di                      ;first char attribute is at offset 1
        mov     al,es:[di]              ;grab first attr
        mov     ah,es:[di+2]            ;grab second attr
        mov     [word ptr oldVTXT],ax   ;record saved attributes
        mov     al,LEDattrM             ;write out the two attributes
        stosb                           ;that will make up our on-screen "LED"
        inc     di
        stosb
        ret
draw_mono ENDP

eras_mono PROC
        inc     di                      ;first char attribute is at offset 1
        mov     ax,[word ptr oldVTXT]   ;retrieve what we need to restore
        stosb                           ;restore 1st attr
        mov     es:[di+1],ah            ;restore 2nd attr (di already +1)
        ret
eras_mono ENDP

draw_40col PROC
        inc     di                      ;first char attribute is at offset 1
        mov     al,es:[di]              ;grab original attribute
        mov     [byte ptr oldVTXT],al   ;save it
        mov     byte ptr es:[di],LEDattrC;paint our "LED"
        ret
draw_40col ENDP

eras_40col PROC
        inc     di                      ;first char attribute is at offset 1
        mov     ax,[word ptr oldVTXT]   ;retrieve what we need to restore
        stosb                           ;restore attr
        ret
eras_40col ENDP

draw_mode4 PROC
;Draws LED bitmap to offset in DI
        push    cx
        push    si

        mov     si,di
        push    si                      ;save for later drawing
        push    ds                      ;swap ds and es:
        push    es
        pop     ds                      ;ds=b800:(loc)
        pop     es
        mov     di,offset oldVRAM       ;es:di = temp vram storage
        mov     cx,4
save4loop:
        lodsw                           ;load word bank 0; si now +2
        stosw
        mov     ax,[si+8192-2]          ;load word bank 1 (0+8192)
        stosw
        add     si,80-2                 ;si next row, +0
        loop    save4loop

        ;paint new "LED" bitmap (immed. values adjusted for little-endian)
        pop     di                      ;retreive our base for drawing

        push    es
        push    ds
        pop     es                      ;es:di = b800:(loc)
        pop     ds
        mov     si,offset LEDbitmap     ;ds:si = bitmap data
        mov     cx,4
putmode4b:
        lodsw                           ;load from 0
        stosw                           ;store to 0 (bank 0), di now +2
        lodsw                           ;load from 2
        mov     es:[di+8192-2],ax       ;store to 0 (bank 1), minding the +2
        add     di,80-2                 ;di = next line of bank 0
        loop    putmode4b

        pop     si
        pop     cx
        ret
LEDbitmap:
        dw 00000h ; 0000000000000000
        dw 0A00Ah ; 0000101010100000
        dw 0E82Bh ; 0010101111101000
        dw 0E82Bh ; 0010101111101000
        dw 0A82Ah ; 0010101010101000
        dw 0A82Ah ; 0010101010101000
        dw 0A00Ah ; 0000101010100000
        dw 00000h ; 0000000000000000
draw_mode4 ENDP

eras_mode4 PROC
        push    cx
        push    si
        mov     si,offset oldVRAM
        mov     cx,4
erasmode4b:
        lodsw                           ;load from 0
        stosw                           ;store to 0 (bank 0), di now +2
        lodsw                           ;load from 2
        mov     es:[di+8192-2],ax       ;store to 2 (bank 1)
        add     di,80-2                 ;di = 4 (bank 0)
        loop    erasmode4b
        pop     si
        pop     cx
        ret
eras_mode4 ENDP

MODE13SHAPE EQU 0 ;Set to 1 for an "LED" shape, but it doesn't show up well
draw_mod13 PROC
eras_mod13 PROC
        IF MODE13SHAPE
        ;NOTs an area in mode 13h in this pattern:
        ;00000000
        ;00111100
        ;01100110
        ;01100110
        ;01111110
        ;01111110
        ;00111100
        ;00000000
        not     word ptr es:[(1*320)+2]
        not     word ptr es:[(1*320)+4]
        not     word ptr es:[(2*320)+1]
        not     word ptr es:[(2*320)+5]
        not     word ptr es:[(3*320)+1]
        not     word ptr es:[(3*320)+5]
        not     word ptr es:[(4*320)+1]
        not     word ptr es:[(4*320)+3]
        not     word ptr es:[(4*320)+5]
        not     word ptr es:[(5*320)+1]
        not     word ptr es:[(5*320)+3]
        not     word ptr es:[(5*320)+5]
        not     word ptr es:[(6*320)+2]
        not     word ptr es:[(6*320)+4]
        ELSE
        push    cx
        mov     cx,8
@row13loop:
        not     word ptr es:[di]
        not     word ptr es:[di+2]
        not     word ptr es:[di+4]
        not     word ptr es:[di+6]
        add     di,320
        loop    @row13loop
        pop     cx
        ENDIF
        ret
eras_mod13 ENDP
draw_mod13 ENDP

draw_null:
eras_null:
        ret

;----------------------------------------------------------------------------
; Indicator (speaker, on-screen "LED", keyboard LED) finish procedures.
; These fire after the real INT 13h call concludes to restore system state.
diskIntLeave PROC
        push    ds
        push    ax

        push    cs
        pop     ds                      ;to make var/table addressing easier

restoreLED:
        test    [i_flags],fLED          ;did we paint a virtual LED?
        jz      restoreKBD              ;skip if not
        push    bx
        xor     bx,bx
        mov     bl,[curvidm]            ;retrieve video mode we're still in
        shl     bl,1                    ;bx = index into vseg and jump tables
        push    es
        push    di
        xor     di,di                   ;erase LED at location 0 (upper left)
        mov     es,[bx+VIDSEGS]         ;es = current active vidram segment
        call    [bx+erastbl]            ;erase the virtual LED on-screen
        pop     di
        pop     es
        pop     bx

restoreKBD:
        test    [i_flags],fKBD          ;did we enable any keyboard LEDs?
        jz      restoreSpkr             ;skip if not
        push    es
        mov     ax,40h
        mov     es,ax                   ;es->BIOS Data Area
        push    dx
        mov     dl,es:[97h]             ;get actual LED flags
        call    setKBDLEDs              ;return kbd LEDs to saved state
        pop     dx
        pop     es

restoreSpkr:
        test    [i_flags],fHED          ;did we make sound?
        jz      doneExitHandler         ;if not, just exit
        mov     al,[cs:oldSpkr]         ;retrieve original speaker state
        out     61h,al                  ;...and restore it

doneExitHandler:
        pop     ax
        pop     ds
        ret
diskIntLeave ENDP


;----------------------------------------------------------------------------
;INT 13h ENTRY POINT
;We have hooked INT 13h (BIOS disk services) and have come here instead of
;the original INT 13h call.  We will check to see if the requested service
;is something that would normally cause HDD physical activity, and perform
;our software indicators if so, or just JMP to the original int13 if not.

ISP_HEADER 13h
        pushf
        push    bx                      ;need an index register
        IF OMITFLOPPY
        cmp     dl,80h                  ;is the target for this call a HDD?
        jb      noindicators            ;if not, skip indicators
        ENDIF
        cmp     ah,0Fh                  ;is this outside our understood calls?
        ja      noindicators            ;if so, just do original int13
        xor     bx,bx
        mov     bl,ah
        cmp     byte ptr [bx+dsvctbl],1 ;does this call do physical activity?
        jne     noindicators            ;if not, don't do any indicators

doindicators:
        pop     bx                      ;restore changed bx
        call    diskIntEnter            ;start indicators
        ;Simulate interrupt call to original INT 13h
        ;pushf                          ;not needed, orig. flags already pushed
        call    ORIG_INT13h             ;pass to original disk interrupt
        call    diskIntLeave            ;stop indicators
        iret                            ;leave int13
noindicators:
        pop     bx                      ;restore potentially-changed bx
        popf                            ;restore flags on entry
        jmp     ORIG_INT13h

resident_code_size equ offset $

TSRcodeEnd@

;-----------------------------------------------------------------------
;Transient portion of TSR begins

_TEXT SEGMENT 'CODE'
        ASSUME cs:_TEXT,ds:NOTHING,es:NOTHING,ss:NOTHING

banner_         db 13,10,'SOFTHDDI v',VERSION_STR,' - Jim Leonard, 2022',13,10,'$'
usage_          db 'Displays "virtual" hard disk LEDs and sounds during disk activity.',13,10
                db 'Intended for use with silent storage, ie. solid-state drives (SD/CF cards).',13,10
                db 10
                db 'Usage:'
                db 9,'SOFTHDDI [LSK]',9,'Install with one or more indicators (see below)',13,10
                db 9,'SOFTHDDI R',9,'Disable and remove from memory',13,10
                db 13,10
                db 'Installation options:',13,10
                db 9,'L',9,'Enable on-screen LED',13,10
                db 9,'S',9,'Enable virtual seek sound',13,10
                db 9,'K',9,'Enable keyboard LED',13,10
;                db 9,'1..9',9,'Volume of click (optional)',13,10
                db 13,10
                db 'Example:',13,10,9,'SOFTHDDI L S',9,'Install with on-screen LED and sound',13,10
                db '$'
installed_      db 'Installed.',13,10,'$'
enableLED_      db 'Virtual LED requested',13,10,'$'
enableKBD_      db 'Keyboard LED requested',13,10,'$'
enableSND_      db 'Virtual seek sound requested',13,10,'$'
PC_no_KBDLEDs_  db 'This program cannot control keyboard LEDs on PC/XT-class hardware.',13,10,'$'
already_inst_   db 'Already installed.',13,10,'To change options, remove with R, then reinstall.',13,10,'$'
cant_remove_    db "Can't remove from memory.",13,10,'$'
uninstalled_    db 'Removed.',13,10,'$'

indicators      db 0
vdetected       db 0

@Startup2 Y                             ;Y = allocate a __psp variable
        push    ds
        pop     es
        ASSUME  ES:_INIT
        push    cs
        pop     ds
        ASSUME  DS:_TEXT
        DISPLAY_STRING banner_
        mov     bx,1000h                ;set memory block to 64K
        mov     ah,4Ah
        int     21h
        mov     si,80h                  ;si->command-line pascal string
        cld
        xor     cx,cx
        seges lodsb
        or      al,al
        jz      showusage
        mov     cl,al                   ;loop through chars on command-line
cmdline_loop:
        seges lodsb                     ;load char from command-line
        call    uppercase               ;al->AL
        cmp     al,'L'
        je      wantLED
        cmp     al,'S'
        je      wantSnd
        cmp     al,'K'
        je      wantKbd
        cmp     al,'R'
        je      removing
cmdcontinue:
        loop    cmdline_loop
        cmp     indicators,0
        jne     installing              ;install if so, otherwise print errmsg
showusage:
        mov     dx,offset _TEXT:usage_
        jmp     exit_with_error

wantLED:
        call    videoid                 ;discover what video card is installed
        or      indicators,fLED
        DISPLAY_STRING enableLED_
        jmp     cmdcontinue

wantSnd:
        or      indicators,fSND
        DISPLAY_STRING enableSND_
        jmp     cmdcontinue

wantKbd:
;We need to stop the user if they try to enable AT keyboard LEDs on an XT
;system, because they'll effectively hang the system with the resulting
;timeouts.  One way to determine if we're on an AT is to check if the
;8255 is PC-type or AT-type, which can be done by exploiting bit 7 at 61h
;(Port B) which is read-write on PC but read-only on AT.  For more
;information, see PCTIM003.TXT by Kris Heidenstrom.
        push    cx
        mov     cx,400h                 ;Six attempts (top bits of CH)
        pushf
        cli                             ;timing-sensitive operation
        in      al,61h                  ;Get Port B contents
        IODELAY
        mov     ah,al                   ;Original value to AH
Flip61Loop:
        xor     ah,10000000b            ;Flip top bit
        mov     al,ah                   ;Get value to AL
        out     61h,al                  ;Write value to port
        in      al,61h                  ;Read it back
        IODELAY
        xor     al,ah                   ;Set bit 7 if value didn't stay
        shl     al,1                    ;Shift bit into carry
        rcl     cx,1                    ;Shift bit into bottom of CX
        jnc     Flip61Loop              ;Loop if more flips (six in total).
        popf                            ;Restore interrupt flag
        test    cl,cl                   ;Was port read/write?  Zero if so.
        pop     cx
        jz      PCXT                    ;If so, PC/XT; if not, AT
        or      indicators,fKBD
        DISPLAY_STRING enableKBD_
        jmp     cmdcontinue
PCXT:
        mov     dx,offset _TEXT:PC_no_KBDLEDs_
        jmp     exit_with_error

removing:
        UNINSTALL cant_uninstall
        ;announce that the resident part has been removed
        push    cs
        pop     ds
        ASSUME  DS:_TEXT
        DISPLAY_STRING uninstalled_
successful_exit:
        mov     ax,4C00h
        int     21h

installing:
        INSTALL_TSR ,BEST,TOPMEM,inst_patch,already_installed

cant_uninstall:
        mov     dx,offset _TEXT:cant_remove_
        jmp     short exit_with_error
already_installed:
        mov     dx,offset _TEXT:already_inst_
exit_with_error:
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h

;Patch the resident portion of the code before going resident
inst_patch:
        push    es
        mov     es,ax
        ASSUME  ES:RESIDENT_CODE
        mov     al,indicators
        mov     i_flags,al
        mov     al,vdetected
        mov     vidcard,al
        pop     es
        ASSUME  ES:NOTHING
        DISPLAY_STRING installed_
        ret


;-----------------------------------------------------------------------
;Helper subroutines for the transient portion of the TSR

uppercase PROC
        cmp     al,'a'                  ;start of lowercase range?
        jb      @@1                     ;bail if outside
        cmp     al,'z'                  ;end of lowercase range?
        ja      @@1                     ;bail if outside
        sub     al,'a'-'A'              ;make uppercase
@@1:
        ret
uppercase ENDP


videoid PROC
;Determine what video hardware is installed
        push    ax
        push    bx
        push    cx
        push    dx

;First, check for VGA or MCGA BIOS display ID function:
findVGA:
        mov     ax,1A00h
        int     10h                     ;1ah = query video display combination
        cmp     al,1Ah                  ;did this function return OK status?
        jne     findEGA                 ;if not, try EGA
        ;convert BIOS DCCs into specific subsystems & displays
        xor     bh,bh                   ;bx = active display
        mov     al,byte ptr cs:[bx+DCCtable] ;look up what card 1Ah returned
        mov     vdetected,al
        jmp     detected

;If that didn't work, check for EGA BIOS display ID function:
findEGA:
        mov     ah,12h                  ;12h = video subsystem configuration
        mov     bl,10h                  ;10h = return video config
        int     10h
        cmp     bl,10h                  ;did BL change?
        je      findCGA                 ;if not, try CGA
        mov     vdetected,h_EGA
        jmp     detected

;Okay, we have either CGA or MDA.  Query 6845 to figure out which one.
findCGA:
        mov     dx,3D4h                 ;DX = CRTC address port for CGA
        call    Find6845
        jc      findMDA                 ;carry flag = 6845 not found at DX
        mov     vdetected,h_CGA
        jmp     detected

findMDA:
        mov     dx,3B4h                 ;DX = CRTC address port for MDA
        call    Find6845
        jc      detected                ;6845 not found, card unknown, bail
        ;We found MDA -- let's see if it's a Hercules card
        mov     dl,0BAh                 ;DX = 3BAh (status port)
        in      al,dx
        and     al,10000000b            ;AH = bit 7 (vertical sync on HGC)
        mov     ah,al                   ;store for later to see if it changes
        mov     cx,8000h
findhgc:
        in      al,dx
        and     al,10000000b            ;isolate vertical sync bit
        cmp     ah,al
        loope   findHGC                 ;wait for bit 7 to change
        jne     isHerc                  ;if bit 7 changed, it's a Hercules
        mov     vdetected,h_MDA         ;otherwise, assume regular MDA
        jmp     detected
isHerc:
        mov     vdetected,h_HGC

detected:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

;translation table for int 13,1a result
DCCtable:
        DB      0
        DB      h_MDA
        DB      h_CGA
        DB      0
        DB      h_EGA
        DB      h_EGA
        DB      0
        DB      h_VGA
        DB      h_VGA
        DB      0
        DB      h_MCGA
        DB      h_MCGA
        DB      h_MCGA
videoid ENDP


Find6845 PROC
;Detect the presence of a 6845 on CGA, MDA, or HGC by writing a register
;on the chip (we use cursor_low) and then reading the value back.
;If the same value is read back, assume the chip is present.
;Caller:  DX = port addr
;Returns: cf set if not present
        push    ax
        mov     al,0Fh
        out     dx,al                   ;select 6845 reg 0Fh (Cursor Low)
        inc     dx
        in      al,dx                   ;AL = current Cursor Low value
        mov     ah,al
        mov     al,66h                  ;AL = arbitrary value
        out     dx,al                   ;try to write to 6845
        IODELAY                         ;wait for 6845 to respond
        in      al,dx
        xchg    ah,al                   ;AH = returned val, AL = original val
        out     dx,al                   ;restore original value
        cmp     ah,66h                  ;test whether 6845 responded
        je      found6845               ;jump if it did (cf is reset)
        stc                             ;set carry flag if no 6845 present
found6845:
        pop     ax
        ret
Find6845 ENDP



_TEXT ENDS

     end INIT


; Miscellaneous notes:
;
; When writing interrupt hooks in assembler, you generally choose between
; optimizing for size (to minimize the size of the TSR in RAM), or speed
; (to impact the system as little as possible).  I mostly optimized for
; speed, as a primary goal was to not impact I/O speed even on slow systems.
; I also wanted the code to be as readable as possible, which can be
; difficult to maintain when optimizing for size.

