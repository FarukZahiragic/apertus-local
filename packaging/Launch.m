// Small native launcher: build against the intended minimum macOS release.
// osacompile bundles a host-provided applet whose own minimum can be much newer.
#import <Cocoa/Cocoa.h>

static NSString *shellQuote(NSString *value) {
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *root = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"apertus-local"];
        NSString *command = [NSString stringWithFormat:@"cd %@ && ./Start.command", shellQuote(root)];
        NSString *escaped = [[command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                                      stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *source = [NSString stringWithFormat:@"tell application \"Terminal\"\nactivate\ndo script \"%@\"\nend tell", escaped];
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        NSDictionary *error = nil;
        if (![script executeAndReturnError:&error]) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:@"Apertus Local could not open Terminal"];
            [alert setInformativeText:[NSString stringWithFormat:@"Allow Terminal automation in System Settings > Privacy & Security > Automation.\n\n%@", error]];
            [NSApp activateIgnoringOtherApps:YES];
            [alert runModal];
            return 1;
        }
        return 0;
    }
}
