import Foundation
import VideoToolbox

/// Runtime hardware detection so one universal binary tunes itself for Apple Silicon or Intel Macs.
enum Hardware {
    static let isAppleSilicon: Bool = {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &v, &size, nil, 0) == 0 && v == 1
    }()
    static let cores = ProcessInfo.processInfo.activeProcessorCount
    static let physicalCores: Int = {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.physicalcpu", &v, &size, nil, 0) == 0 ? Int(v) : cores
    }()
    static let cpuName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }()
    /// True when VideoToolbox offers a hardware HEVC encoder (Apple media engine, or Intel Quick Sync on Intel Macs).
    static let hasHardwareHEVC: Bool = {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let encoders = list as? [[String: Any]] else { return isAppleSilicon }
        return encoders.contains { e in
            (e[kVTVideoEncoderList_CodecType as String] as? UInt32) == kCMVideoCodecType_HEVC &&
            (e[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
    }()
    static var engineName: String { isAppleSilicon ? "Apple Silicon media engine" : "T2 / Intel Quick Sync" }
    static var summary: String {
        "\(isAppleSilicon ? "Apple Silicon" : "Intel") · \(physicalCores) cores/\(cores) threads · HW HEVC \(hasHardwareHEVC ? "yes" : "no")"
    }
    /// VideoToolbox jobs mostly load the media engine, so two can overlap; x264/x265 already use every core, so one.
    /// Measured on a 2018 15" MacBook Pro (i9-8950HK, T2): with two VT HEVC jobs, macOS puts one on the T2
    /// encoder (hevc.ave, ~100 fps at 1080p) and the other on Intel Quick Sync (hevc.gva, ~50 fps), so 2 beats 1.
    static func defaultConcurrency(for preset: HBPreset) -> Int {
        preset.isVideoToolbox && hasHardwareHEVC ? 2 : 1
    }
    static func preferredPreset(in presets: [HBPreset]) -> HBPreset? {
        hasHardwareHEVC ? presets.first { $0.name == "H.265 Apple VideoToolbox 1080p" } : nil
    }
}
