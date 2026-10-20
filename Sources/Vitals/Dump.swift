import Foundation

/// `Vitals --dump [--bench]`: prints one snapshot as JSON after two samples (so rates are real) and exits.
enum Dump {
    static func run() -> Never {
        let s = Sampler()
        _ = s.sampleNow()
        // nettop runs twice, 2 s apart, for per-process network rates.
        s.processes.primeNetwork(interval: 2)
        let snap = s.sampleNow()
        if CommandLine.arguments.contains("--bench") { bench(s) }
        let data = (try? JSONSerialization.data(withJSONObject: snap, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }

    /// --dump --bench: how much one full 2-second tick costs (sample + JSON), and resident memory.
    private static func bench(_ s: Sampler) {
        func cpuSeconds() -> Double {
            var u = rusage(); getrusage(RUSAGE_SELF, &u)
            return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        }
        let n = 20
        let c0 = cpuSeconds(), t0 = Date()
        for _ in 0..<n { _ = AppDelegate.encode(s.sampleNow()) }
        let perTick = (cpuSeconds() - c0) / Double(n)
        s.setWantProcesses(false)
        let c1 = cpuSeconds()
        for _ in 0..<n { _ = s.sampleNow() }
        let idleTick = (cpuSeconds() - c1) / Double(n)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        let msg = String(format: "bench: %.1f ms CPU per tick with process rows (%.2f%% of one core at 2 s), %.1f ms without (%.2f%%); resident %.0f MB; wall %.1f s\n",
                         perTick * 1000, perTick / 2 * 100, idleTick * 1000, idleTick / 2 * 100, Double(info.resident_size) / 1048576, Date().timeIntervalSince(t0))
        FileHandle.standardError.write(Data(msg.utf8))
    }
}
