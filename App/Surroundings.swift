import AppKit
import IOKit.ps

/// Is the Mac on battery or in Low Power Mode? Then the notch draws fewer frames.
enum Power {
    static var shouldSave: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == "Battery Power"
    }
}

/// Is another app filling this screen (a full-screen video, a Keynote or PowerPoint show, a game)?
enum FullScreen {
    static func covers(_ screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let me = ProcessInfo.processInfo.processIdentifier
        // Window bounds are in global display coordinates: origin at the top left of the main screen.
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        let target = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            if abs(r.minX - target.minX) < 1, abs(r.minY - target.minY) < 1,
               abs(r.width - target.width) < 1, abs(r.height - target.height) < 1 {
                return true
            }
        }
        return false
    }
}
