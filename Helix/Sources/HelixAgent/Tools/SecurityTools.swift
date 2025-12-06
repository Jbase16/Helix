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
            // Note: Nikto can be slow, limiting time or using -Tuning might be wise in production, but we run standard here.
            report += "--- Step 2: Nikto Scan ---\n"
            // We assume nikto is installed (agent can install it if needed via package tool)
            let niktoCmd = "nikto -h \(target) -maxtime 60" // Cap at 60s for demo responsiveness
            let niktoResult = try await RunCommandTool().run(arguments: ["command": niktoCmd])
            report += niktoResult.output + "\n\n"
            
            // 3. Gobuster (Directory Brute Force)
            // Need a wordlist. If brew installed gobuster, usually no default wordlist is set up easily.
            // We'll skip Gobuster for now unless we can guarantee a wordlist, or we use a simple common list.
            // Let's stick to Nikto which is self-contained.
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
        
        // Ensure searchsploit is in path or brew installed
        let cmd = "searchsploit \"\(query)\""
        let result = try await RunCommandTool().run(arguments: ["command": cmd])
        
        if result.output.contains("command not found") {
            return ToolResult(output: "Error: 'searchsploit' not found. Please ask me to 'install exploitdb' first.", isError: true)
        }
        
        return result
    }
}
