#ifndef NINECRAFT_NANO_UI_H
#define NINECRAFT_NANO_UI_H

/* The engine and input see the native UI canvas. Only renderLevel uses the
 * smaller world buffer. The setting is opt-in and specific to PE 0.8.1. */
void nano_ui_configure(int *width, int *height);
void nano_ui_register_gl_hooks(void);
int nano_ui_install(void *game, int version);
void nano_ui_shutdown(void);

#endif
