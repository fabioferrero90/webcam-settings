// Access to the UVC (USB Video Class) controls of a webcam via IOKit.
#pragma once

enum { UVC_CAM = 0, UVC_PU = 1 };  // camera terminal, processing unit
enum { UVC_GET_CUR = 0x81, UVC_GET_MIN = 0x82, UVC_GET_MAX = 0x83, UVC_GET_RES = 0x84, UVC_GET_DEF = 0x87 };

int uvc_open(void);                 // opens the first connected UVC webcam; 1 if found
const char *uvc_name(void);
int uvc_vid(void);
int uvc_pid(void);
int uvc_supported(int unit, int bit);
int uvc_get(int unit, int sel, int req, int len, long *out);  // 0 on success
int uvc_set(int unit, int sel, int len, long val);           // 0 on success
