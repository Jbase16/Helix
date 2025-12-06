import Foundation
import AppKit

enum BrowserError: LocalizedError {
    case noActiveBrowser
    case scriptExecutionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noActiveBrowser: return "No supported browser found active (Safari or Chrome)."
        case .scriptExecutionFailed(let msg): return "Browser script failed: \(msg)"
        }
    }
}

actor BrowserService {
    
    static let shared = BrowserService()
    
    enum Browser {
        case safari
        case chrome
        
        var appName: String {
            switch self {
            case .safari: return "Safari"
            case .chrome: return "Google Chrome"
            }
        }
    }
    
    /// Detects if Safari or Chrome is the frontmost supported browser.
    private func getActiveBrowser() -> Browser? {
        let workspace = NSWorkspace.shared
        // We iterate running apps to find if one of ours is frontmost-ish
        // Or simpler: check which one is running and has a window?
        // Better: Check active app via NSWorkspace
        
        guard let frontApp = workspace.frontmostApplication else { return nil }
        let bundleID = frontApp.bundleIdentifier?.lowercased() ?? ""
        
        if bundleID.contains("safari") {
            return .safari
        }
        if bundleID.contains("chrome") {
            return .chrome
        }
        
        // Fallback: Check if they are running and visible if Helix is frontmost
        return nil
    }
    
    func getActivePageContext() async throws -> (url: String, title: String) {
        // Scripts return "URL|Title"
        
        let chromeScript = """
        tell application "Google Chrome"
            if it is running then
                if (count of windows) > 0 then
                    set curURL to URL of active tab of front window
                    set curTitle to title of active tab of front window
                    return curURL & "|" & curTitle
                end if
            end if
        end tell
        """
        
        if let result = runAppleScript(chromeScript) {
            return parseScriptResult(result)
        }
        
        let safariScript = """
        tell application "Safari"
            if it is running then
                if (count of windows) > 0 then
                    set curURL to URL of current tab of front window
                    set curName to name of current tab of front window
                    return curURL & "|" & curName
                end if
            end if
        end tell
        """
        
        if let result = runAppleScript(safariScript) {
            return parseScriptResult(result)
        }
        
        // No browser active or no windows
        return ("", "")
    }
    
    func runJavaScript(_ js: String) async throws -> String {
        let escapedJS = escapeForAppleScript(js)
        
        let chromeScript = """
        tell application "Google Chrome"
            if it is running and (count of windows) > 0 then
                execute active tab of front window javascript "\(escapedJS)"
            end if
        end tell
        """
        
        if let res = runAppleScript(chromeScript) {
            return res
        }
        
        let safariScript = """
        tell application "Safari"
            if it is running and (count of windows) > 0 then
                do JavaScript "\(escapedJS)" in current tab of front window
            end if
        end tell
        """
        
        if let res = runAppleScript(safariScript) {
            return res
        }
        
        throw BrowserError.noActiveBrowser
    }
    
    func getSessionData() async throws -> String {
        // JavaScript to dump cookies and localStorage
        let dumpScript = """
        (function() {
            var cookies = document.cookie;
            var storage = {};
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                storage[key] = localStorage.getItem(key);
            }
            return JSON.stringify({
                cookies: cookies,
                localStorage: storage,
                url: window.location.href,
                title: document.title
            });
        })();
        """
        // Double escaping because it's Swift -> AppleScript -> JS
        // The previous runJavaScript method handles one layer.
        // But JSON.stringify returns quotes which might break AppleScript's "return ...".
        // Instead of modifying runJavaScript, we reuse it but need to be careful about the return value.
        // AppleScript `do JavaScript` in Chrome returns the result. In Safari too.
        
        return try await runJavaScript(dumpScript)
    }

    // MARK: - Helpers
    
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: source) {
            let descriptor = scriptObject.executeAndReturnError(&error)
            if error == nil {
                return descriptor.stringValue
            } else {
                // print("AppleScript Error: \(error!)") 
            }
        }
        return nil
    }
    
    private func parseScriptResult(_ result: String) -> (String, String) {
        let components = result.split(separator: "|", maxSplits: 1).map(String.init)
        if components.count == 2 {
            return (components[0], components[1])
        } else if components.count == 1 {
            return (components[0], "")
        }
        return ("", "")
    }
    
    private func escapeForAppleScript(_ str: String) -> String {
        // Simple escape for double quotes and backslashes
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
