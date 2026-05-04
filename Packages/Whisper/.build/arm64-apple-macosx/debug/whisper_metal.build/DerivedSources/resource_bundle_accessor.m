#import <Foundation/Foundation.h>

NSBundle* whisper_metal_SWIFTPM_MODULE_BUNDLE() {
    NSURL *bundleURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"Whisper_whisper_metal.bundle"];

    NSBundle *preferredBundle = [NSBundle bundleWithURL:bundleURL];
    if (preferredBundle == nil) {
      return [NSBundle bundleWithPath:@"/Users/andreev-denis/Desktop/dev/OpenVoice/Packages/Whisper/.build/arm64-apple-macosx/debug/Whisper_whisper_metal.bundle"];
    }

    return preferredBundle;
}