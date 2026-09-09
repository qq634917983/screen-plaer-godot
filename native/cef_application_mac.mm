// Bridge Godot's existing NSApplication subclass to the event-loop protocol
// required by CEF. Keep Godot's sendEvent implementation and restore it at unload.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include "include/cef_application_mac.h"

static Class original_class = Nil;
static Class bridge_class = Nil;
static IMP original_send_event = nullptr;
static BOOL handling_event = NO;

static BOOL is_handling(id, SEL) { return handling_event; }
static void set_handling(id, SEL, BOOL value) { handling_event = value; }
static void send_event(id self, SEL selector, NSEvent *event) {
    BOOL previous = handling_event;
    handling_event = YES;
    @try {
        reinterpret_cast<void (*)(id, SEL, NSEvent *)>(original_send_event)(self, selector, event);
    } @finally {
        handling_event = previous;
    }
}

void screenplayer_install_cef_application() {
    if (!NSApp || [NSApp conformsToProtocol:@protocol(CefAppProtocol)]) return;
    original_class = object_getClass(NSApp);
    original_send_event = class_getMethodImplementation(original_class, @selector(sendEvent:));
    bridge_class = objc_allocateClassPair(original_class, "ScreenPlayerCEFApplication", 0);
    if (!bridge_class) return;
    class_addProtocol(bridge_class, @protocol(CefAppProtocol));
    class_addMethod(bridge_class, @selector(isHandlingSendEvent), (IMP)is_handling, "c@:");
    class_addMethod(bridge_class, @selector(setHandlingSendEvent:), (IMP)set_handling, "v@:c");
    class_addMethod(bridge_class, @selector(sendEvent:), (IMP)send_event, "v@:@");
    objc_registerClassPair(bridge_class);
    object_setClass(NSApp, bridge_class);
}

void screenplayer_uninstall_cef_application() {
    if (bridge_class && NSApp && object_getClass(NSApp) == bridge_class) {
        object_setClass(NSApp, original_class);
        objc_disposeClassPair(bridge_class);
    }
    bridge_class = Nil;
}
