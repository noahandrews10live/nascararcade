/*
 * Speedway Thunder force-feedback helper.
 *
 * The game (Godot) can't drive a steering wheel's force feedback itself, so it
 * starts this small program and streams it the steering force over UDP on
 * 127.0.0.1:24570, 60 times a second:
 *     "F <force -1..1> <rumble 0..1>\n"     set the force
 *     "Q\n"                                   quit
 * The helper answers the sender every two seconds with "OK <wheel name>" or
 * "NONE", and quits by itself if the game goes quiet for five seconds.
 *
 * Windows: DirectInput 8 constant-force effect (every FFB wheel supports it).
 * Linux:   SDL2 haptics.
 *
 * Build: native/build.sh
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define PORT 24570

#ifdef _WIN32
#define DIRECTINPUT_VERSION 0x0800
#include <winsock2.h>
#include <windows.h>
#include <dinput.h>
typedef SOCKET sock_t;
static double now_s(void) { return GetTickCount64() / 1000.0; }
static void sleep_ms(int ms) { Sleep(ms); }
#else
#include <SDL2/SDL.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/select.h>
#include <unistd.h>
#include <time.h>
typedef int sock_t;
static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static void sleep_ms(int ms) { usleep(ms * 1000); }
#endif

static char g_name[128] = "";

/* ---------------------------------------------------------------- Windows */
#ifdef _WIN32
static LPDIRECTINPUT8 g_di = NULL;
static LPDIRECTINPUTDEVICE8 g_dev = NULL;
static LPDIRECTINPUTEFFECT g_eff = NULL;
static DICONSTANTFORCE g_cf;
static DIEFFECT g_effect;
static DWORD g_axes[1] = { DIJOFS_X };
static LONG g_dir[1] = { 0 };

static BOOL CALLBACK enum_cb(const DIDEVICEINSTANCE *inst, VOID *ctx) {
	(void)ctx;
	if (FAILED(IDirectInput8_CreateDevice(g_di, &inst->guidInstance, &g_dev, NULL)))
		return DIENUM_CONTINUE;
	snprintf(g_name, sizeof g_name, "%ls", inst->tszProductName);
	return DIENUM_STOP;
}

static int ffb_open(void) {
	if (FAILED(DirectInput8Create(GetModuleHandle(NULL), DIRECTINPUT_VERSION, &IID_IDirectInput8, (void **)&g_di, NULL)))
		return 0;
	IDirectInput8_EnumDevices(g_di, DI8DEVCLASS_GAMECTRL, enum_cb, NULL, DIEDFL_ATTACHEDONLY | DIEDFL_FORCEFEEDBACK);
	if (!g_dev)
		return 0;
	IDirectInputDevice8_SetDataFormat(g_dev, &c_dfDIJoystick2);
	/* Exclusive access is required for force feedback; a hidden window will do. */
	HWND hwnd = CreateWindowExA(0, "STATIC", "ffb", 0, 0, 0, 0, 0, NULL, NULL, GetModuleHandle(NULL), NULL);
	IDirectInputDevice8_SetCooperativeLevel(g_dev, hwnd, DISCL_EXCLUSIVE | DISCL_BACKGROUND);
	DIPROPDWORD ac;
	ac.diph.dwSize = sizeof ac;
	ac.diph.dwHeaderSize = sizeof(DIPROPHEADER);
	ac.diph.dwObj = 0;
	ac.diph.dwHow = DIPH_DEVICE;
	ac.dwData = DIPROPAUTOCENTER_OFF;
	IDirectInputDevice8_SetProperty(g_dev, DIPROP_AUTOCENTER, &ac.diph);
	IDirectInputDevice8_Acquire(g_dev);
	g_cf.lMagnitude = 0;
	memset(&g_effect, 0, sizeof g_effect);
	g_effect.dwSize = sizeof(DIEFFECT);
	g_effect.dwFlags = DIEFF_CARTESIAN | DIEFF_OBJECTOFFSETS;
	g_effect.dwDuration = INFINITE;
	g_effect.dwGain = DI_FFNOMINALMAX;
	g_effect.dwTriggerButton = DIEB_NOTRIGGER;
	g_effect.cAxes = 1;
	g_effect.rgdwAxes = g_axes;
	g_effect.rglDirection = g_dir;
	g_effect.cbTypeSpecificParams = sizeof(DICONSTANTFORCE);
	g_effect.lpvTypeSpecificParams = &g_cf;
	if (FAILED(IDirectInputDevice8_CreateEffect(g_dev, &GUID_ConstantForce, &g_effect, &g_eff, NULL)))
		return 0;
	IDirectInputEffect_Start(g_eff, 1, 0);
	return 1;
}

static void ffb_set(float force) {
	if (!g_eff)
		return;
	g_cf.lMagnitude = (LONG)(force * DI_FFNOMINALMAX);
	IDirectInputEffect_SetParameters(g_eff, &g_effect, DIEP_TYPESPECIFICPARAMS | DIEP_START);
}

static void ffb_close(void) {
	if (g_eff) { IDirectInputEffect_Stop(g_eff); IDirectInputEffect_Release(g_eff); }
	if (g_dev) { IDirectInputDevice8_Unacquire(g_dev); IDirectInputDevice8_Release(g_dev); }
	if (g_di) IDirectInput8_Release(g_di);
}

/* ------------------------------------------------------------------ Linux */
#else
static SDL_Haptic *g_hap = NULL;
static int g_eid = -1;
static SDL_HapticEffect g_he;

static int ffb_open(void) {
	if (SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_HAPTIC) != 0)
		return 0;
	for (int i = 0; i < SDL_NumHaptics(); i++) {
		SDL_Haptic *h = SDL_HapticOpen(i);
		if (!h)
			continue;
		if (SDL_HapticQuery(h) & SDL_HAPTIC_CONSTANT) {
			g_hap = h;
			snprintf(g_name, sizeof g_name, "%s", SDL_HapticName(i));
			break;
		}
		SDL_HapticClose(h);
	}
	if (!g_hap)
		return 0;
	if (SDL_HapticQuery(g_hap) & SDL_HAPTIC_AUTOCENTER)
		SDL_HapticSetAutocenter(g_hap, 0);
	memset(&g_he, 0, sizeof g_he);
	g_he.type = SDL_HAPTIC_CONSTANT;
	g_he.constant.direction.type = SDL_HAPTIC_CARTESIAN;
	g_he.constant.direction.dir[0] = 1;
	g_he.constant.length = SDL_HAPTIC_INFINITY;
	g_he.constant.level = 0;
	g_eid = SDL_HapticNewEffect(g_hap, &g_he);
	if (g_eid < 0)
		return 0;
	SDL_HapticRunEffect(g_hap, g_eid, SDL_HAPTIC_INFINITY);
	return 1;
}

static void ffb_set(float force) {
	if (g_eid < 0)
		return;
	g_he.constant.level = (Sint16)(force * 32767.0f);
	SDL_HapticUpdateEffect(g_hap, g_eid, &g_he);
}

static void ffb_close(void) {
	if (g_hap) SDL_HapticClose(g_hap);
	SDL_Quit();
}
#endif

/* ------------------------------------------------------------------ main */
int main(void) {
#ifdef _WIN32
	WSADATA wsa;
	WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
	int have = ffb_open();
	sock_t s = socket(AF_INET, SOCK_DGRAM, 0);
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof addr);
	addr.sin_family = AF_INET;
	addr.sin_port = htons(PORT);
	addr.sin_addr.s_addr = inet_addr("127.0.0.1");
	if (bind(s, (struct sockaddr *)&addr, sizeof addr) != 0) {
		fprintf(stderr, "ffb_helper: port %d busy\n", PORT);
		return 1;
	}
	struct sockaddr_in from;
	int have_from = 0;
	double last_msg = now_s(), last_report = 0.0;
	float force = 0.0f, rumble = 0.0f;
	int flip = 0;
	char buf[256];
	for (;;) {
		fd_set rd;
		FD_ZERO(&rd);
		FD_SET(s, &rd);
		struct timeval tv = { 0, 5000 };
		if (select((int)s + 1, &rd, NULL, NULL, &tv) > 0) {
#ifdef _WIN32
			int fl = sizeof from;
#else
			socklen_t fl = sizeof from;
#endif
			int n = recvfrom(s, buf, sizeof buf - 1, 0, (struct sockaddr *)&from, &fl);
			if (n > 0) {
				buf[n] = 0;
				have_from = 1;
				last_msg = now_s();
				if (buf[0] == 'Q')
					break;
				if (buf[0] == 'F')
					sscanf(buf + 1, "%f %f", &force, &rumble);
			}
		}
		/* Rumble rides on the steady force as a fast buzz (kerbs, bumps, contact). */
		flip = !flip;
		float out = force + (flip ? rumble : -rumble) * 0.25f;
		if (out > 1.0f) out = 1.0f;
		if (out < -1.0f) out = -1.0f;
		ffb_set(have ? out : 0.0f);
		double t = now_s();
		if (have_from && t - last_report > 2.0) {
			last_report = t;
			char msg[160];
			snprintf(msg, sizeof msg, have ? "OK %s" : "NONE", g_name);
			sendto(s, msg, (int)strlen(msg), 0, (struct sockaddr *)&from, sizeof from);
		}
		if (t - last_msg > 5.0)
			break; /* the game has gone */
		sleep_ms(1);
	}
	ffb_set(0.0f);
	ffb_close();
	return 0;
}
