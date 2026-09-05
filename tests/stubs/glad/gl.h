/* Rendering is not exercised by the input event test. The real ARM build uses
 * generated GLAD headers; these declarations let unused rendering be discarded. */
typedef int GLint;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef double GLdouble;
#define GL_MODELVIEW 0
#define GL_CURRENT_PROGRAM 0
#define GL_MATRIX_MODE 0
#define GL_COLOR_BUFFER_BIT 0
#define GL_CURRENT_BIT 0
#define GL_DEPTH_BUFFER_BIT 0
#define GL_ENABLE_BIT 0
#define GL_LINE_BIT 0
#define GL_VIEWPORT_BIT 0
#define GL_TEXTURE_2D 0
#define GL_DEPTH_TEST 0
#define GL_CULL_FACE 0
#define GL_ALPHA_TEST 0
#define GL_BLEND 0
#define GL_SRC_ALPHA 0
#define GL_ONE_MINUS_SRC_ALPHA 0
#define GL_FALSE 0
#define GL_PROJECTION 0
#define GL_TRIANGLES 0
#define GL_LINE_LOOP 0
void glGetIntegerv(int, GLint *);
void glPushAttrib(int);
void glUseProgram(GLuint);
void glViewport(int, int, int, int);
void glDisable(int);
void glEnable(int);
void glBlendFunc(int, int);
void glDepthMask(int);
void glMatrixMode(int);
void glPushMatrix(void);
void glLoadIdentity(void);
void glOrtho(double, double, double, double, double, double);
void glColor4f(float, float, float, float);
void glBegin(int);
void glVertex2f(float, float);
void glEnd(void);
void glLineWidth(float);
void glPopMatrix(void);
void glPopAttrib(void);
