import Darwin
import Foundation

/// The kernel's process table, read via `sysctl(KERN_PROC_ALL)`.
///
/// Command-line tools and helper processes never appear in
/// `NSWorkspace.runningApplications` (it lists GUI apps only), so detectors
/// that need them — coding agents, a call's in-meeting helper — read this.
enum ProcessTable {

    /// Every process's short name (`p_comm`), which the kernel caps at 16 bytes.
    static func names() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        let count = size / stride + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        size = count * stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        let actual = min(count, size / stride)
        var names = Set<String>()
        for index in 0..<actual {
            var proc = procs[index]
            let name = withUnsafeBytes(of: &proc.kp_proc.p_comm) { raw -> String in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }
}
