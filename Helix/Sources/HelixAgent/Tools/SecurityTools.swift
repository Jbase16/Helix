import Foundation

/// Tool to perform a multi-step reconnaissance chain on a target.
struct AutoReconTool: Tool {
    var name: String { "auto_recon" }
    var description: String { "Performs an autonomous reconnaissance chain: 1. Nmap scan 2. If web ports (80/443) open, runs Nikto and Gobuster. Returns a consolidated report." }
    var usageSchema: String { "auto_recon(target=\"<ip_or_domain>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let target = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        
        // Dependency Check
        let checkNmap = try await RunCommandTool().run(arguments: ["command": "which nmap"])
        if checkNmap.isError {
            return ToolResult(output: "Error: 'nmap' is not installed. Please run `install_package(name=\"nmap\")` first.", isError: true)
        }
        
        var report = "=== AutoRecon Report for \(target) ===\n\n"
        
        // 1. Nmap Scan (Fast scan for top ports)
        report += "--- Step 1: Nmap Scan ---\n"
        let nmapCmd = "nmap -T4 -F \(target)"
        let nmapResult = try await RunCommandTool().run(arguments: ["command": nmapCmd])
        
        if nmapResult.isError {
            return ToolResult(output: "Nmap failed: \(nmapResult.output)", isError: true)
        }
        report += nmapResult.output + "\n\n"
        
        // Check for Web Ports
        let hasWeb = nmapResult.output.contains("80/tcp open") || nmapResult.output.contains("443/tcp open") || nmapResult.output.contains("8080/tcp open")
        
        if hasWeb {
            report += "--- Web Ports Detected. Initiating Web Recon ---\n\n"
            
            // 2. Nikto Scan (Web Vulnerability Scanner)
            let checkNikto = try await RunCommandTool().run(arguments: ["command": "which nikto"])
            if checkNikto.isError {
                 report += "Warning: 'nikto' is not installed. Skipping web vulnerability scan. Please run `install_package(name=\"nikto\")` to enable this step.\n\n"
            } else {
                report += "--- Step 2: Nikto Scan ---\n"
                let niktoCmd = "nikto -h \(target) -maxtime 60"
                let niktoResult = try await RunCommandTool().run(arguments: ["command": niktoCmd])
                report += niktoResult.output + "\n\n"
            }
        } else {
            report += "--- No Web Ports Detected. Skipping Web Recon. ---\n"
        }
        
        return ToolResult(output: report, isError: false)
    }
}

/// Tool to search Exploit-DB for known vulnerabilities.
struct ExploitSearchTool: Tool {
    var name: String { "search_exploits" }
    var description: String { "Searches Exploit-DB (searchsploit) for known exploits matching a query (e.g., 'Apache 2.4')." }
    var usageSchema: String { "search_exploits(query=\"<software_version>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let query = arguments["query"] else {
             return ToolResult(output: "Error: Missing 'query' argument.", isError: true)
        }
        
        let check = try await RunCommandTool().run(arguments: ["command": "which searchsploit"])
        if check.isError {
            return ToolResult(output: "Error: 'searchsploit' (Exploit-DB) is not installed. Please run `install_package(name=\"exploitdb\")` first.", isError: true)
        }
        
        let cmd = "searchsploit \"\(query)\""
        let result = try await RunCommandTool().run(arguments: ["command": cmd])
        return result
    }
}
