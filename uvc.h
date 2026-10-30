// Access to the UVC (USB Video Class) controls of a webcam via IOKit.
#pragma once

enum { UVC_CAM = 0, UVC_PU = 1 };  // camera terminal, processing unit
enum { UVC_GET_CUR = 0x81, UVC_GET_MIN = 0x82, UVC_GET_MAX = 0x83, UVC_GET_RES = 0x84, UVC_GET_DEF = 0x87 };

typedef struct { char name[128]; int vid, pid; unsigned location; } uvc_info;

int uvc_list(uvc_info *out, int max);  // connected UVC webcams, returns how many were found
int uvc_open(unsigned location);       // opens the webcam on that USB location (0 = first found); 1 if found
const char *uvc_name(void);
int uvc_vid(void);
int uvc_pid(void);
int uvc_supported(int unit, int bit);
int uvc_get(int unit, int sel, int req, int len, long *out);  // 0 on success
int uvc_set(int unit, int sel, int len, long val);           // 0 on success
