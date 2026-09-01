#pragma once

#include <stdbool.h>
#include <SDL.h>

int miyoo_input_init(SDL_Window *window);
void miyoo_input_tick(SDL_Window *window, bool *running);
void miyoo_input_draw_cursor(SDL_Window *window);
void miyoo_input_shutdown(void);
