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
    run_command(command="<command_string>")
    </tool_code>
    """
    let requiresPermission = true
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let command = arguments["command"] else {
            return ToolResult(output: "Error: Missing 'command' argument.", isError: true)
        }
        
        // Guard Rail: Prevent Agent from running internal tools as shell commands
        let internalTools = ["nuclei_scan", "auto_recon", "verify_xss", "verify_sqli", "verify_idor", "analyze_logic", "generate_submission"]
        let cmdName = command.components(separatedBy: " ").first ?? ""
        
        if internalTools.contains(cmdName) {
            return ToolResult(output: "Error: '\(cmdName)' is an INTERNAL HELIX TOOL, not a shell command. \n\nCorrect Usage: Call it as a tool directly.\nExample: <tool_code>\(cmdName)(\(cmdName == "nuclei_scan" ? "target=\"...\"" : "..."))</tool_code>\n\nDO NOT use run_command() for this.", isError: true)
        }
        
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        // Run via /bin/zsh to support pipes, wildcards, etc.
        // Inject common PATHs to ensure brew/user tools are found
        var environment = ProcessInfo.processInfo.environment
        let currentPath = environment["PATH"] ?? ""
        // Prepend common homebrew/local paths
        let newPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
        environment["PATH"] = newPath
        process.environment = environment
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Read output
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            process.waitUntilExit()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            let combined = output + (errorOutput.isEmpty ? "" : "\nSTDERR:\n\(errorOutput)")
            
            if process.terminationStatus == 0 {
                return ToolResult(output: combined.trimmingCharacters(in: .whitespacesAndNewlines), isError: false)
            } else {
                return ToolResult(output: "Command failed (Exit \(process.terminationStatus)):\n\(combined)", isError: true)
            }
            
        } catch {
            return ToolResult(output: "Failed to run command: \(error.localizedDescription)", isError: true)
        }
    }
}
