#include "uvc.h"
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>

typedef struct { UInt8 vcIf, unitId[2]; UInt32 controls[2]; } layout;

static IOUSBDeviceInterface **dev;
static layout lay;
static uvc_info info;

// Finds the Video Control interface, the camera terminal and the processing unit
// in the configuration descriptor, along with their control bitmaps.
static int parse(IOUSBDeviceInterface **d, layout *l) {
    IOUSBConfigurationDescriptorPtr cfg;
    if ((*d)->GetConfigurationDescriptorPtr(d, 0, &cfg)) return 0;
    UInt8 *p = (UInt8 *)cfg, *end = p + USBToHostWord(cfg->wTotalLength);
    int isVC = 0, found = 0;
    *l = (layout){0};
    for (; p + 2 <= end && p[0]; p += p[0]) {
        if (p[1] == 0x04) {
            isVC = p[5] == 0x0E && p[6] == 0x01;
            if (isVC && !found) { l->vcIf = p[2]; found = 1; }
        } else if (isVC && p[1] == 0x24) {
            if (p[2] == 0x02 && (p[4] | p[5] << 8) == 0x0201) {
                l->unitId[UVC_CAM] = p[3];
                for (int i = 0; i < p[14] && i < 4; i++) l->controls[UVC_CAM] |= (UInt32)p[15 + i] << (8 * i);
            } else if (p[2] == 0x05) {
                l->unitId[UVC_PU] = p[3];
                for (int i = 0; i < p[7] && i < 4; i++) l->controls[UVC_PU] |= (UInt32)p[8 + i] << (8 * i);
            }
        }
    }
    return found;
}

// Walks the connected UVC webcams. Fills `list` when given; keeps open the one on `want`
// (0 = the first) when `open` is set. Returns how many webcams were seen.
static int scan(uvc_info *list, int max, int open, unsigned want) {
    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOUSBDeviceClassName), &it)) return 0;
    io_service_t svc;
    int n = 0;
    while ((svc = IOIteratorNext(it))) {
        IOCFPlugInInterface **plug;
        SInt32 score;
        IOUSBDeviceInterface **d = NULL;
        if (!IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score)) {
            (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&d);
            IODestroyPlugInInterface(plug);
        }
        layout l;
        if (d && parse(d, &l)) {
            UInt16 v, p;
            UInt32 loc = 0;
            (*d)->GetDeviceVendor(d, &v);
            (*d)->GetDeviceProduct(d, &p);
            (*d)->GetLocationID(d, &loc);
            uvc_info i = { .vid = v, .pid = p, .location = loc };
            io_name_t nm;
            IORegistryEntryGetName(svc, nm);
            strlcpy(i.name, nm, sizeof i.name);
            if (list && n < max) list[n] = i;
            n++;
            if (open && !dev && (!want || want == loc)) { dev = d; lay = l; info = i; d = NULL; }
        }
        if (d) (*d)->Release(d);
        IOObjectRelease(svc);
    }
    IOObjectRelease(it);
    return n;
}

int uvc_list(uvc_info *out, int max) { return scan(out, max, 0, 0); }

int uvc_open(unsigned location) {
    if (dev) { (*dev)->Release(dev); dev = NULL; }
    scan(NULL, 0, 1, location);
    return dev != NULL;
}

const char *uvc_name(void) { return info.name; }
int uvc_vid(void) { return info.vid; }
int uvc_pid(void) { return info.pid; }

int uvc_supported(int unit, int bit) {
    return unit >= 0 && unit < 2 && lay.unitId[unit] && (lay.controls[unit] >> bit & 1);
}

static IOReturn req(int unit, int in, int r, int sel, void *buf, int len) {
    if (!dev) return kIOReturnNotOpen;
    IOUSBDevRequest q = {
        .bmRequestType = in ? 0xA1 : 0x21, .bRequest = r,
        .wValue = sel << 8, .wIndex = (lay.unitId[unit] << 8) | lay.vcIf,
        .wLength = len, .pData = buf };
    return (*dev)->DeviceRequest(dev, &q);
}

int uvc_get(int unit, int sel, int r, int len, long *out) {
    UInt8 b[4] = {0};
    IOReturn e = req(unit, 1, r, sel, b, len);
    if (e) return e;
    if (len == 1) *out = b[0];
    else if (len == 2) *out = (SInt16)(b[0] | b[1] << 8);
    else *out = (SInt32)(b[0] | b[1] << 8 | b[2] << 16 | (UInt32)b[3] << 24);
    return 0;
}

int uvc_set(int unit, int sel, int len, long val) {
    UInt8 b[4] = { val & 0xFF, val >> 8 & 0xFF, val >> 16 & 0xFF, val >> 24 & 0xFF };
    return req(unit, 0, 0x01, sel, b, len);
}
