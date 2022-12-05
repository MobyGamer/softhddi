# SOFTHDDI
## Software Hard Disk Drive Indicators for DOS

Provides simulated hard disk activity "LED"s and seeking sounds.
Intended for MS-DOS systems with solid-state hard drives that lack both, so that disk activity can again be seen/heard.

Three hard disk "indicators" are available, and can be enabled in any combination:

 - An on-screen "LED" that appears in the upper left corner
 - An audible "click" that simulates HDD head seek noise
 - Keyboard CAPSLOCK/NUMLOCK/SCROLLLOCK indicator LEDs

Run "SOFTHDDI" with no arguments to see command-line usage.

## Impact

The TSR uses roughly 1KB of RAM when resident, and automatically loads itself into upper memory blocks if present.

The on-screen "LED" and speaker click indicators are effectively free (they don't slow down the system or I/O, even on a 4.77 MHz system), but the keyboard LEDs indicator can result in a slowdown (see **Limitations** below).

## Implementation Notes

Painting the "virtual LED" on-screen is handled differently based on what video mode the system is currently in.  The goal is to display a flashing square in the upper left corner whenever there is disk activity.  This is typically handled by:

- Color and B&W text modes:  Colors are changed to become lightred-on-red.
- Mono text mode:  Colors are changed to become darkgreen-on-green. (On some monitors this attribute can result in a "halo", enhancing the effect.)
- Graphics modes (fixed palettes):  An 8x8-pixel "LED" graphic is painted.
- Graphics modes (redefinable palettes):  An 8x8 square area is created by flipping all bits in that area.  This method was chosen to have the least impact to the system while still having a high likelyhood of visibility no matter what the color palette is set to.

To prevent locking up an XT-class system, SOFTHDDI will not allow enabling keyboard LEDs unless the PC is an AT (80286) or higher system.

CGA "snow" avoidance is fully handled.  To prevent unnecessary slowdown on non-CGA video cards, the video hardware is detected on startup so that snow avoidance is only performed on true CGA hardware.

SOFTHDDI supports dual-monitor DOS systems, and will display the virtual "LED" on the current active monitor.

## Limitations

### On-screen "LED"

Video modes above 13h (ie. SVGA/VESA) are ignored.  Supporting those would take up too much resident RAM and CPU time.  Besides, if you can run those modes, you have a fast system, and would likely never see the "LED" in practice anyway.  Other indicators (sound, keyboard LEDs) work fine in SVGA.

Not all video modes below 13h are supported; more support will be added as time and interest permits.  (Want to add more standard modes? Go for it, and submit a pull request.)

Unchained VGA modes are not yet detected and handled correctly, which results in some (harmless) graphical corruption in the upper right corner.

### Keyboard LEDs

Enabling the keyboard LEDs will result in a loss of I/O performance, due to the amount of hardware reads and writes necessary to interact with the keyboard controller safely.  Slowdowns between 2x and 4x have been observed on a 200 MHz Pentium Pro.

If the keyboard controller is busy when this program needs to flash the LEDs, the LEDs may temporarily stop illuminating.  If this happens, hit numlock, capslock, or scrollock to return LEDs to normal.

### Speaker clicks

The volume of the speaker click is currently fixed (+5V rise time is 1ms) and cannot be made louder/softer. This volume level was chosen to be as loud as possible while simultaneously having minimal impact to the system.

If playing digitized audio through the PC speaker, such as in RealSound games, the speaker click may stop working.  Make any normal sound through the speaker to return functionality.  (One quick way is to type `CTRL-G` at the DOS prompt.)

## Future Improvements

- Add support for missing modes < 13h (Hercules graphics, Tandy, etc.)
- Make the on-screen LED in graphics mode look nicer, as if it were a sprite overlay on the background
- Explore potential size/speed improvements, such as only installing and calling the exact code paths needed

## Acknowledgements

This TSR relies on the Alternate Multiplex Interrupt Specification authored by Ralf Brown for its terminate-and-stay-resident functionality. AMIS-compliant TSRs have several advantages over typical TSRs, including:

  - Only resident code goes resident, resulting in smaller RAM usage
  - Can automatically load themselves to upper ram if UMBs are available
  - Can load and unload TSRs in any order

The AMIS specification, and code portions used here, are (C) Ralf Brown. For a description of AMIS and an example AMIS library, consult `AMISL092.ZIP`.

Information on programming the keyboard LEDs courtesy of Frank van Gilluwe.

Information on determining PC vs. AT 8255 from Kris Heidenstrom (RIP).

Methodology for detecting video hardware adapted from Richard Wilton.

Greetz to VileR, who drew a CGA mode4+mode6 "LED" bitmap on short notice :-)
