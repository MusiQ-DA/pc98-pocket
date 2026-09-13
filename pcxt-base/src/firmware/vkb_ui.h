#ifndef VKB_UI_H
#define VKB_UI_H

// Set up the OSD framebuffer and draw the keyboard once.
void vkb_ui_init(void);

// Poll controller 1: L1 toggles the keyboard, the D-pad moves the cursor.
void vkb_ui_tick(void);

// True while the virtual keyboard or the settings menu owns the OSD framebuffer.
int vkb_ui_overlay_open(void);

// Open the virtual keyboard as a key picker for button btn (a BIND_* id): the next key chosen
// with A is bound to that button instead of typed into the guest. Called from the settings menu.
void vkb_ui_open_picker(int btn);

#endif
