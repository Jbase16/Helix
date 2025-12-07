//
//  ShellTools.swift
//  Helix
//
//  Created by Helix Agent.
//

import Foundation



/// Tool to run a shell command.
struct RunCommandTool: Tool {
    let name = "run_command"
    let description = "Executes a shell command on the system. Use with caution."
    let usageSchema = """
    <tool_code>
    run_command(command="<command_string>", timeout="<seconds_optional>")
    </tool_code>
    """
    let requiresPermission = true
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let command = arguments["command"] else {
            return ToolResult(output: "Error: Missing 'command' argument.", isError: true)
        }
        let timeoutSeconds = Double(arguments["timeout"] ?? "")
        
        // Guard Rail: Prevent Agent from running internal tools as shell commands
        let internalTools = ["nuclei_scan", "auto_recon", "verify_xss", "verify_sqli", "verify_idor", "analyze_logic", "generate_submission"]
        let cmdName = command.components(separatedBy: " ").first ?? ""
        let matchesInternal = internalTools.contains(cmdName) || internalTools.contains(where: { cmdName.hasPrefix("\($0)(") })
        
        if matchesInternal {
            return ToolResult(output: "Error: '\(cmdName)' is an INTERNAL HELIX TOOL, not a shell command. \n\nCorrect Usage: Call it as a tool directly.\nExample: <tool_code>\(cmdName)(\(cmdName == "nuclei_scan" ? "target=\"...\"" : "..."))</tool_code>\n\nDO NOT use run_command() for this.", isError: true)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            
            // Thread-safe readers
            let outputReader = PipeReader()
            let errorReader = PipeReader()
            let stateQueue = DispatchQueue(label: "com.helix.runcommand.state")
            var didResume = false
            var timedOut = false
            
            // Run via /bin/zsh
            var environment = ProcessInfo.processInfo.environment
            let currentPath = environment["PATH"] ?? ""
            let newPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
            environment["PATH"] = newPath
            process.environment = environment
            
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // Disable zsh glob expansion to avoid failures like '--script=http-vuln*' when patterns don't match.
            process.arguments = ["-c", "set -o noglob; " + command]
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            print("[RunCommandTool] DEBUG: Executing: \(command)")
            
            // Use handlers to read data safely
            pipe.fileHandleForReading.readabilityHandler = { handle in
                outputReader.append(handle.availableData)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorReader.append(handle.availableData)
            }
            
            var timeoutTask: Task<Void, Never>?
            let cancelTimeoutTask: () -> Void = {
                stateQueue.sync {
                    timeoutTask?.cancel()
                }
            }
            let markTimedOut: () -> Void = {
                stateQueue.sync { timedOut = true }
            }
            let isTimedOut: () -> Bool = {
                stateQueue.sync { timedOut }
            }
            
            if let timeoutSeconds, timeoutSeconds > 0 {
                timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    guard process.isRunning else { return }
                    markTimedOut()
                    process.interrupt()
                    // Fallback terminate if still alive shortly after.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                }
            }
            
            let finalize: (ToolResult) -> Void = { result in
                stateQueue.sync {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: result)
                }
            }
            
            process.terminationHandler = { proc in
                // Cleanup handlers
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                cancelTimeoutTask()
                
                // Read final accumulated data
                let outputData = outputReader.read()
                let errorData = errorReader.read()
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let combined = output + (errorOutput.isEmpty ? "" : "\nSTDERR:\n\(errorOutput)")
                
                let didTimeOut = isTimedOut()
                
                if proc.terminationStatus == 0 && !didTimeOut {
                    finalize(ToolResult(output: combined.trimmingCharacters(in: .whitespacesAndNewlines), isError: false))
                } else if didTimeOut {
                    let msg = "Command timed out after \(timeoutSeconds ?? 0) seconds.\n\(combined)"
                    finalize(ToolResult(output: msg.trimmingCharacters(in: .whitespacesAndNewlines), isError: true))
                } else {
                    finalize(ToolResult(output: "Command failed (Exit \(proc.terminationStatus)):\n\(combined)", isError: true))
                }
            }
            
            do {
                try process.run()
            } catch {
                timeoutTask?.cancel()
                finalize(ToolResult(output: "Failed to run command: \(error.localizedDescription)", isError: true))
            }
        }
    }
}
