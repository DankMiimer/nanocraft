#ifndef NANOCRAFT_INPUT_SENSITIVITY_H
#define NANOCRAFT_INPUT_SENSITIVITY_H

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

#define NC_SENS_MIN 10
#define NC_SENS_MAX 200
#define NC_SENS_STEP 10
#define NC_SENS_COUNT 20
#define NC_CAMERA_DEFAULT 100
#define NC_CURSOR_DEFAULT 20

typedef struct {
    int camera;
    int cursor;
} nc_sensitivity;

/* One atomic file holds both percentages. A missing or malformed file uses
 * the same defaults in the menu and the input reader. No game options change. */
static inline nc_sensitivity nc_sensitivity_read(const char *path)
{
    nc_sensitivity value = { NC_CAMERA_DEFAULT, NC_CURSOR_DEFAULT };
    char buf[80], *next, *end;
    long camera, cursor;
    FILE *file = fopen(path, "r");
    if (!file) return value;
    size_t size = fread(buf, 1, sizeof(buf) - 1, file);
    int extra = fgetc(file);
    int failed = ferror(file);
    fclose(file);
    if (failed || extra != EOF) return value;
    buf[size] = '\0';
    errno = 0;
    camera = strtol(buf, &next, 10);
    if (errno || next == buf || !isspace((unsigned char)*next)) return value;
    cursor = strtol(next, &end, 10);
    if (errno || end == next) return value;
    while (isspace((unsigned char)*end)) ++end;
    if (end != buf + size || camera < NC_SENS_MIN || camera > NC_SENS_MAX ||
        cursor < NC_SENS_MIN || cursor > NC_SENS_MAX ||
        camera % NC_SENS_STEP || cursor % NC_SENS_STEP) return value;
    value.camera = (int)camera;
    value.cursor = (int)cursor;
    return value;
}

/* Camera 100% exactly preserves the existing relative mouse movement.
 * Cursor 100% uses the old 240px baseline: the same fraction of the panel
 * per second at 120 and 240. Smaller defaults allow individual cells to be hit. */
static inline float nc_motion_gain(nc_sensitivity value, int in_world,
                                   int extent)
{
    return in_world ? value.camera / 100.0f :
           (value.cursor / 100.0f) * (extent / 240.0f);
}

#endif
