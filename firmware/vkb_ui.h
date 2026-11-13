#ifndef VKB_UI_H
#define VKB_UI_H

// Set up the OSD framebuffer and draw the keyboard once.
void vkb_ui_init(void);

// Poll controller 1: L1 toggles the keyboard, the D-pad moves the cursor.
void vkb_ui_tick(void);

// The timer interrupt's fast path (start.S): {ok, CONT1_KEY, OSD_RASTER, timer period}.
// vkb_ui_tick sets ok when its next call would do nothing unless one of those
// two words changes (no overlay up, the button word adopted, no reset walk);
// irq_vec then compares the two words and re-arms the timer without saving the
// context or entering C. main sets the period before arming the timer.
#include <stdint.h>
extern volatile uint32_t vkb_irq_fast[4];

// Open the virtual keyboard as a key picker for button btn (a BIND_* id): the next key chosen
// with A is bound to that button instead of typed into the guest. Called from the settings menu.
void vkb_ui_open_picker(int btn);

#endif
