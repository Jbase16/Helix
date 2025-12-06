import Foundation

/// Tool to perform "Cognitive Analysis" - logic mapping and secret mining.
struct AnalyzeLogicTool: Tool {
    var name: String { "analyze_logic" }
    var description: String { "Performs deep cognitive analysis of a web target. 1. Fetches HTML/JS. 2. Mines for secrets (API keys, tokens). 3. Maps client-side API routes. 4. Genetates logic attack hypotheses." }
    var usageSchema: String { "analyze_logic(target=\"<url>\")" }
    var requiresPermission: Bool { true }
    var shouldCachePermission: Bool { true }
    
    func run(arguments: [String : String]) async throws -> ToolResult {
        guard let target = arguments["target"] else {
             return ToolResult(output: "Error: Missing 'target' argument.", isError: true)
        }
        
        var report = "=== 🧠 COGNITIVE LOGIC ANALYSIS: \(target) ===\n"
        
        // 1. Fetch Main HTML via Headless(ish) Browser for SPA support
        // User reported Curl failing on SPAs. We must use the BrowserService to render the DOM.
        
        var html = ""
        do {
            try await BrowserService.shared.navigateTo(url: target)
            // Wait for SPA hydration (3s)
            try await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            
            html = try await BrowserService.shared.runJavaScript("document.documentElement.outerHTML")
            report += "✅ Successfully fetched RENDERED DOM from Browser (SPA Support Active).\n"
        } catch {
             report += "⚠️ Browser fetch failed: \(error.localizedDescription). Falling back to Curl (Static).\n"
             // Fallback
             let curlCmd = "curl -s -L --max-time 10 -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' \"\(target)\""
             let htmlResult = try await RunCommandTool().run(arguments: ["command": curlCmd])
             html = htmlResult.output
        }
        
        if html.isEmpty {
            return ToolResult(output: "Failed to fetch target HTML (Browser & Curl). Cannot perform analysis.", isError: true)
        }
        
        report += "### 1. Secret Mining (HTML & JS)\n"
        let secrets = mineSecrets(in: html, source: "Main Page")
        if secrets.isEmpty {
            report += "- No obvious secrets found in HTML.\n"
        } else {
            report += secrets.map { "- [HTML] \($0)" }.joined(separator: "\n") + "\n"
        }
        
        // 2. Extract and Fetch JS Files
        let jsLinks = extractJSLinks(from: html, baseURL: target)
        report += "\n### 2. Client-Side Asset Analysis (\(jsLinks.count) scripts found)\n"
        
        var allEndpoints: Set<String> = []
        
        for link in jsLinks.prefix(5) { // Limit to top 5 scripts to save time/bandwidth
            report += "- Analyzing \(link)...\n"
            let jsCmd = "curl -s -L --max-time 10 \"\(link)\""
            let jsResult = try await RunCommandTool().run(arguments: ["command": jsCmd])
            
            if !jsResult.isError {
                let jsContent = jsResult.output
                // Mine Secrets in JS
                let jsSecrets = mineSecrets(in: jsContent, source: link)
                if !jsSecrets.isEmpty {
                    report += jsSecrets.map { "  - ⚠️ SECRET: \($0)" }.joined(separator: "\n") + "\n"
                }
                
                // Extract Routes
                let routes = extractRoutes(from: jsContent)
                allEndpoints.formUnion(routes)
            }
        }
        
        report += "\n### 3. Discovered API Endpoints (Logic Surface)\n"
        if allEndpoints.isEmpty {
            report += "No distinct API endpoints extracted.\n"
        } else {
            let sortedRoutes = allEndpoints.sorted()
            report += sortedRoutes.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        
        // 4. Logic Hypotheses
        report += "\n### 4. Logic Attack Hypotheses (AI Generated)\n"
        report += generateHypotheses(endpoints: Array(allEndpoints), html: html)
        
        report += "\n=== End Analysis ===\n"
        return ToolResult(output: report, isError: false)
    }
    
    // MARK: - Helpers
    
    private func mineSecrets(in text: String, source: String) -> [String] {
        var findings: [String] = []
        
        // Common Regexes for Secrets
        let patterns: [String: String] = [
            "AWS Access Key": "AKIA[0-9A-Z]{16}",
            "Generic API Key": "(?i)(?:api_key|apikey|secret|token)[\"':=][\\s]*[\\w\\-]{16,64}",
            "Authorization Bearer": "Bearer\\s+[a-zA-Z0-9\\-\\._~\\+/]+=*",
            "Stripe Key": "(?:sk|pk)_(?:test|live)_[0-9a-zA-Z]{24}",
            "Google API": "AIza[0-9A-Za-z\\-_]{35}"
        ]
        
        for (name, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for match in results {
                    if let range = Range(match.range, in: text) {
                        let matchedStr = String(text[range])
                        // Truncate for privacy in report, but show it exists
                        let redacted = matchedStr.prefix(8) + "..."
                        findings.append("\(name) found: \(redacted)")
                    }
                }
            }
        }
        return findings
    }
    
    private func extractJSLinks(from html: String, baseURL: String) -> [String] {
        // Simple regex to find src="..."
        // Real parser would be better, but regex is sufficient for 'hacker' vibe
        var links: [String] = []
        let pattern = #"<script[^>]+src=["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    var path = String(html[range])
                    // Normalize relative URLs
                    if !path.lowercased().hasPrefix("http") {
                        // Very naive URL joining
                        let base = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
                        if path.hasPrefix("/") { path = String(path.dropFirst()) }
                        links.append(base + path)
                    } else {
                        links.append(path)
                    }
                }
            }
        }
        return Array(Set(links)) // Dedup
    }
    
    private func extractRoutes(from js: String) -> [String] {
        var routes: [String] = []
        // Look for string literals that look like paths: "/api/v1/..."
        // Pattern: simple quote, slash, alphanumeric/dashes, etc.
        let pattern = #"["'](\/[a-zA-Z0-9_\-\/\{\}]+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: js, range: NSRange(js.startIndex..., in: js))
            for match in matches {
                if let range = Range(match.range(at: 1), in: js) {
                    let r = String(js[range])
                    if r.count > 1 && !r.contains(" ") && !r.contains("\n") {
                         routes.append(r)
                    }
                }
            }
        }
        return Array(Set(routes)).filter { $0.count < 60 } // Dedup and sanity length check
    }
    
    private func generateHypotheses(endpoints: [String], html: String) -> String {
        var hypos = ""
        
        // Simple heuristic-based hypotheses (The "AI" part)
        // In a real agent, we might ask the LLM loop to analyze this. 
        // For a tool run, we use rule-based logic to simulate "Basic AI".
        
        if endpoints.contains(where: { $0.contains("/user") || $0.contains("/profile") }) {
            hypos += "- 🕵️‍♂️ **IDOR Opportunity**: Found user-related endpoints. Try iterating IDs in `/user/{id}` requests.\n"
        }
        
        if endpoints.contains(where: { $0.contains("admin") || $0.contains("dashboard") }) {
            hypos += "- 🛡️ **Privilege Escalation**: Admin routes detected. Test for broken access control (BAC) on `/admin` endpoints.\n"
        }
        
        if endpoints.contains(where: { $0.contains("upload") || $0.contains("file") }) {
             hypos += "- 📂 **File Upload**: Check for unrestricted file upload vulnerabilities (RCE).\n"
        }
        
        if html.lowercased().contains("csrf") {
             hypos += "- 🔐 **CSRF Logic**: Page contains CSRF tokens. Check if they are validated on state-changing requests.\n"
        }
        
        if hypos.isEmpty {
            hypos += "No specific high-confidence logic flaws detected based on surface analysis. Recommend manual fuzzing.\n"
        }
        
        return hypos
    }
}
