import Foundation

/// Tool to perform a multi-step reconnaissance chain on a target.
struct AutoReconTool: Tool {
    var name: String { "auto_recon" }
    var description: String { "Performs an autonomous reconnaissance chain: 1. Nmap scan 2. If web ports (80/443) open, runs Nikto and Gobuster. Returns a consolidated report." }
    var usageSchema: String { "auto_recon(target=\"<ip_or_domain>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        return try await run(arguments: arguments, onStatus: nil)
    }
    
    func run(arguments: [String : String], onStatus: ((String) -> Void)? = nil) async throws -> ToolResult {
        guard let targetRaw = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        
        // 1. Sanitize Target for NMAP / domain-only tooling
        // Remove https/http
        var nmapTarget = targetRaw
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        // Remove trailing path/fragments (e.g. /#/ or /index.html)
        if let slashIndex = nmapTarget.firstIndex(of: "/") {
            nmapTarget = String(nmapTarget[..<slashIndex])
        }
        // Remove bad chars that might have crept in (like trailing dots or # if no slash was present)
        nmapTarget = nmapTarget.trimmingCharacters(in: CharacterSet(charactersIn: ".#"))
        
        // 2. Prepare Target for WEB TOOLS (Full URL)
        // Ensure it has protocol
        var webURL = targetRaw
        if !webURL.lowercased().hasPrefix("http") {
             webURL = "https://" + webURL
        }
        
        // Dependency Check
        var missing: [String] = []
        
        let checkNmap = try await RunCommandTool().run(arguments: ["command": "which nmap"])
        if checkNmap.isError {
            missing.append("nmap (install_package name=\"nmap\")")
        }
        let checkSubfinder = try await RunCommandTool().run(arguments: ["command": "which subfinder"])
        if checkSubfinder.isError { missing.append("subfinder (install_package name=\"subfinder\")") }
        let checkNaabu = try await RunCommandTool().run(arguments: ["command": "which naabu"])
        if checkNaabu.isError { missing.append("naabu (install_package name=\"naabu\")") }
        let checkHttpx = try await RunCommandTool().run(arguments: ["command": "which httpx"])
        if checkHttpx.isError { missing.append("httpx (install_package name=\"httpx\")") }
        
        if missing.contains(where: { $0.hasPrefix("nmap") }) {
            let list = missing.joined(separator: ", ")
            return ToolResult(output: "Error: Missing critical dependency.\nInstall required tools: \(list)", isError: true)
        }
        
        var report = "=== 🛡️ HELIX VULNERABILITY REPORT 🛡️ ===\n"
        report += "Target Host: \(nmapTarget)\n"
        report += "Target URL: \(webURL)\n"
        report += "Date: \(Date())\n\n"
        
        // 0. Subdomain Enumeration (Subfinder)
        onStatus?("subfinder")
        report += "### 0. Subdomain Discovery (subfinder)\n"
        var discoveredHosts: [String] = []
        if checkSubfinder.isError {
            report += "⚠️ subfinder not installed. Run `install_package(name=\"subfinder\")`.\n\n"
        } else {
            let subfinderCmd = "subfinder -silent -timeout 8 -max-time 30 -d \(nmapTarget)"
            let subfinderResult = try await RunCommandTool().run(arguments: ["command": subfinderCmd, "timeout": "35"])
            if subfinderResult.isError || subfinderResult.output.isEmpty {
                report += "⚠️ Subfinder produced no output or failed.\n\n"
            } else {
                discoveredHosts = subfinderResult.output
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let limited = discoveredHosts.prefix(50).joined(separator: "\n")
                report += "Discovered hosts (showing up to 50):\n```\n\(limited)\n```\n\n"
            }
        }
        
        // 0.5 Host Probing (naabu fast)
        onStatus?("naabu")
        report += "### 0.5. Port Probe (naabu)\n"
        if checkNaabu.isError {
            report += "⚠️ naabu not installed. Run `install_package(name=\"naabu\")`.\n\n"
        } else {
            let naabuCmd = "naabu -host \(nmapTarget) -p 80,443,8080,8443 -rate 1000 -timeout 3000 -exclude-cdn -silent -no-color"
            let naabuResult = try await RunCommandTool().run(arguments: ["command": naabuCmd, "timeout": "40"])
            if naabuResult.isError || naabuResult.output.isEmpty {
                report += "⚠️ naabu produced no output or failed.\n\n"
            } else {
                report += "Open ports (naabu):\n```\n\(naabuResult.output)\n```\n\n"
            }
        }
        
        // 1. HTTP Service Probe (httpx)
        onStatus?("httpx")
        report += "### 1. HTTP Probe (httpx)\n"
        if checkHttpx.isError {
            report += "⚠️ httpx not installed. Run `install_package(name=\"httpx\")`.\n\n"
        } else {
            var inputTargets = [nmapTarget]
            inputTargets.append(contentsOf: discoveredHosts)
            inputTargets = Array(Set(inputTargets)).filter { !$0.isEmpty }
            let joined = inputTargets.joined(separator: "\n")
            let httpxCmd = "printf \"%s\" \"\(joined)\" | httpx -silent -status-code -title -follow-redirects -timeout 6 -no-color"
            let httpxResult = try await RunCommandTool().run(arguments: ["command": httpxCmd, "timeout": "50"])
            if httpxResult.isError || httpxResult.output.isEmpty {
                report += "⚠️ httpx produced no output or failed.\n\n"
            } else {
                report += "Reachable HTTP services:\n```\n\(httpxResult.output)\n```\n\n"
            }
        }
        
        // 2. Nmap Scan (Optimized for speed)
        onStatus?("nmap")
        report += "### 2. Network / Service Recon (Nmap Fast)\n"
        let nmapCmd = "nmap -Pn -F -T4 -n --host-timeout 45s --open \(nmapTarget)"
        let nmapResult = try await RunCommandTool().run(arguments: ["command": nmapCmd, "timeout": "60"])
        
        if nmapResult.isError {
            report += "⚠️ Nmap Warning: \(nmapResult.output)\n\n"
        } else {
            report += "```\n\(nmapResult.output)\n```\n\n"
        }
        
        // Logic: Decide if Web Recon is needed
        let nmapRaw = nmapResult.output
        let hasWebPorts = nmapRaw.contains("80/tcp") || nmapRaw.contains("443/tcp") || nmapRaw.contains("8080/tcp")
        let isDomain = nmapTarget.contains(".")
        
        if hasWebPorts || isDomain {
            onStatus?("nuclei")
            report += "### 3. Web Vulnerability Recon (Nuclei)\n"
            
            // 2A. Nuclei Scan (Fast & Silent)
            let checkNuclei = try await RunCommandTool().run(arguments: ["command": "which nuclei"])
            if checkNuclei.isError {
                report += "\n⚠️ 'nuclei' not installed. Run `install_package(name=\"nuclei\")`.\n"
            } else {
                // Run critical/high severity scan
                let nucleiCmd = "NUCLEI_UPDATE_CHECK=false nuclei -u \(webURL) -s critical,high -silent -timeout 6 -duc -no-color"
                // Nuclei can prompt for templates on first run; enforce a timeout to avoid hanging the agent.
                let nucleiResult = try await RunCommandTool().run(arguments: ["command": nucleiCmd, "timeout": "45"])
                if nucleiResult.output.isEmpty {
                     report += "No critical/high vulnerabilities found by Nuclei.\n"
                } else {
                     report += "```\n\(nucleiResult.output)\n```\n"
                }
            }
            
            // 2B. Cognitive Logic Analysis (AI Engine)
            // (Only if users asked for it explicitly? No, auto_recon implies full suite. But logic analysis uses tokens. Let's keep it but maybe it's fast enough 5-10s?)
            // report += "\n### 3. Cognitive Logic Analysis...\n"
            // skip for speed unless specifically requested via another tool
        } else {
            report += "### 2. Web Recon Skipped (No web ports or domain detected)\n"
        }
        
        report += "\n=== End of Report ===\n"
        
        // Short summary
        report += "\nSummary:\n"
        if !missing.isEmpty {
            report += "- Missing tools: \(missing.joined(separator: ", "))\n"
        } else {
            report += "- Core tooling present (nmap, subfinder, naabu, httpx"
            if !checkNmap.isError { report += ", nuclei" }
            report += ")\n"
        }
        report += "- Target: \(nmapTarget)\n"
        report += "- Web scan: \(hasWebPorts || isDomain ? "performed" : "skipped")\n"
        report += "- See sections above for details.\n"
        
        return ToolResult(output: report, isError: false)
    }
}

/// Tool to run Nuclei specifically (standalone).
struct NucleiTool: Tool {
    var name: String { "nuclei_scan" }
    var description: String { "Runs ProjectDiscovery Nuclei scanner. Industry standard for bug bounty. Detects CVEs, misconfigurations, and logic bugs." }
    var usageSchema: String { "nuclei_scan(target=\"<url>\", severity=\"<critical|high|medium|low|info>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let target = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        let severity = arguments["severity"] ?? "critical,high,medium"
        
        let check = try await RunCommandTool().run(arguments: ["command": "which nuclei"])
        if check.isError {
             return ToolResult(output: "Error: 'nuclei' is not installed. Please run `install_package(name=\"nuclei\")` first.", isError: true)
        }
        
        // Strip protocol for nuclei? Nuclei handles URLs fine, but let's ensure it has one if missing, or leave as is.
        // Nuclei prefers full URLs (http://...) for web scanning.
        // If the user provided just "domain.com", we might want to prepend http/https or let nuclei handle it.
        // Nuclei is smart. We'll pass it raw but sanitized of spaces.
        let cleanTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let cmd = "nuclei -u \"\(cleanTarget)\" -s \(severity)"
        return try await RunCommandTool().run(arguments: ["command": cmd])
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
