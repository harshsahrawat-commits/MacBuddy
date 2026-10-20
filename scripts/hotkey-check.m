#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <stdio.h>
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        UInt32 modifiers = controlKey | optionKey | cmdKey | shiftKey;
        UInt32 keys[] = { kVK_F20, kVK_F19, kVK_F18 };
        EventHotKeyRef first=NULL, duplicate=NULL;
        OSStatus status=-1; UInt32 key=0;
        for(int i=0;i<3;i++) {
            key=keys[i];
            status=RegisterEventHotKey(key,modifiers,(EventHotKeyID){'MBT1',1},GetApplicationEventTarget(),0,&first);
            if(status==noErr)break;
        }
        if(status!=noErr) { fprintf(stderr,"Cannot reserve a test-only F18-F20 shortcut: %d\n",(int)status);return 2; }
        OSStatus conflict=RegisterEventHotKey(key,modifiers,(EventHotKeyID){'MBT2',2},GetApplicationEventTarget(),0,&duplicate);
        if(duplicate)UnregisterEventHotKey(duplicate);
        UnregisterEventHotKey(first);
        if(conflict==noErr) { fputs("FAIL duplicate shortcut was accepted\n",stderr); return 1; }
        EventHotKeyRef retry=NULL;
        status=RegisterEventHotKey(key,modifiers,(EventHotKeyID){'MBT3',3},GetApplicationEventTarget(),0,&retry);
        if(retry)UnregisterEventHotKey(retry);
        if(status!=noErr) { fprintf(stderr,"FAIL shortcut did not release: %d\n",(int)status);return 1; }
        printf("PASS native global-hotkey conflict (%d) and release/re-registration; user's M shortcut unchanged\n",(int)conflict);
    }
    return 0;
}
