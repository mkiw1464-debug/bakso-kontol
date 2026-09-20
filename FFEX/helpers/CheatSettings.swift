import Foundation
import Combine

// MARK: - CheatSettings — all feature toggles, syncs to localConfig.json

final class CheatSettings: ObservableObject {

    static let shared = CheatSettings()

    // ESP
    @Published var espEnabled:     Bool    = true
    @Published var espLine:        Bool    = true
    @Published var espBox:         Bool    = false
    @Published var espHealth:      Bool    = false
    @Published var espName:        Bool    = false
    @Published var espPlayerCount: Bool    = true

    // AIM
    @Published var aimEnabled:        Bool    = false
    @Published var aimType:           AimType = .silent
    @Published var aimTarget:         AimTarget = .head
    @Published var aimIgnoreKnockdown:Bool    = true
    @Published var aimDrawFov:        Bool    = false
    @Published var aimFovValue:       Double  = 80.0

    // MISC
    @Published var miscNoRecoil:    Bool = false
    @Published var miscSpeed:       Bool = false
    @Published var miscFastLanding: Bool = false
    @Published var miscFastMedkit:  Bool = false
    @Published var miscFastRevive:  Bool = false

    enum AimType: String, CaseIterable {
        case legit  = "legit"
        case silent = "silent"
        var label: String { rawValue == "legit" ? "Legit" : "Silent" }
    }

    enum AimTarget: String, CaseIterable {
        case head  = "head"
        case neck  = "neck"
        case body  = "body"
        case leg   = "leg"
        var label: String { rawValue.capitalized }
    }

    private init() { load() }

    // MARK: - Persist to UserDefaults (mirror written to localConfig on inject)

    private let ud = UserDefaults.standard
    private let prefix = "ffex.cheat."

    func save() {
        ud.set(espEnabled,      forKey: prefix+"esp_enabled")
        ud.set(espLine,         forKey: prefix+"esp_line")
        ud.set(espBox,          forKey: prefix+"esp_box")
        ud.set(espHealth,       forKey: prefix+"esp_health")
        ud.set(espName,         forKey: prefix+"esp_name")
        ud.set(espPlayerCount,  forKey: prefix+"esp_player_count")
        ud.set(aimEnabled,      forKey: prefix+"aim_enabled")
        ud.set(aimType.rawValue,forKey: prefix+"aim_type")
        ud.set(aimTarget.rawValue,forKey:prefix+"aim_target")
        ud.set(aimIgnoreKnockdown,forKey:prefix+"aim_ignore_knockdown")
        ud.set(aimDrawFov,      forKey: prefix+"aim_draw_fov")
        ud.set(aimFovValue,     forKey: prefix+"aim_fov_value")
        ud.set(miscNoRecoil,    forKey: prefix+"misc_no_recoil")
        ud.set(miscSpeed,       forKey: prefix+"misc_speed")
        ud.set(miscFastLanding, forKey: prefix+"misc_fast_landing")
        ud.set(miscFastMedkit,  forKey: prefix+"misc_fast_medkit")
        ud.set(miscFastRevive,  forKey: prefix+"misc_fast_revive")
    }

    func load() {
        espEnabled      = ud.object(forKey: prefix+"esp_enabled")     as? Bool ?? true
        espLine         = ud.object(forKey: prefix+"esp_line")        as? Bool ?? true
        espBox          = ud.object(forKey: prefix+"esp_box")         as? Bool ?? false
        espHealth       = ud.object(forKey: prefix+"esp_health")      as? Bool ?? false
        espName         = ud.object(forKey: prefix+"esp_name")        as? Bool ?? false
        espPlayerCount  = ud.object(forKey: prefix+"esp_player_count")as? Bool ?? true
        aimEnabled      = ud.object(forKey: prefix+"aim_enabled")     as? Bool ?? false
        aimType         = AimType(rawValue:   ud.string(forKey: prefix+"aim_type")   ?? "silent") ?? .silent
        aimTarget       = AimTarget(rawValue: ud.string(forKey: prefix+"aim_target") ?? "head")   ?? .head
        aimIgnoreKnockdown = ud.object(forKey: prefix+"aim_ignore_knockdown") as? Bool ?? true
        aimDrawFov      = ud.object(forKey: prefix+"aim_draw_fov")    as? Bool ?? false
        aimFovValue     = ud.object(forKey: prefix+"aim_fov_value")   as? Double ?? 80.0
        miscNoRecoil    = ud.object(forKey: prefix+"misc_no_recoil")  as? Bool ?? false
        miscSpeed       = ud.object(forKey: prefix+"misc_speed")      as? Bool ?? false
        miscFastLanding = ud.object(forKey: prefix+"misc_fast_landing") as? Bool ?? false
        miscFastMedkit  = ud.object(forKey: prefix+"misc_fast_medkit")  as? Bool ?? false
        miscFastRevive  = ud.object(forKey: prefix+"misc_fast_revive")  as? Bool ?? false
    }

    // MARK: - Feature file names (XOR obfuscated — same key used in patch)
    // Each feature maps to a deterministic filename derived from feature name + secret
    // Patch scans Documents folder for these filenames to know what's enabled

    private static let xorKey: UInt8 = 0x5A

    static func featureFileName(_ feature: String) -> String {
        // Derive filename: XOR feature name bytes, take first 8 hex chars
        let bytes = feature.utf8.map { $0 ^ xorKey }
        return bytes.prefix(4).map { String(format: "%02x", $0) }.joined() + ".dat"
    }

    // Feature file names (computed once)
    static let fnEspEnabled   = featureFileName("esp_enabled")
    static let fnEspLine      = featureFileName("esp_line")
    static let fnEspBox       = featureFileName("esp_box")
    static let fnEspHealth    = featureFileName("esp_health")
    static let fnEspName      = featureFileName("esp_name")
    static let fnAimEnabled   = featureFileName("aim_enabled")
    static let fnAimType      = featureFileName("aim_type")
    static let fnAimTarget    = featureFileName("aim_target")
    static let fnAimIgnoreKD  = featureFileName("aim_ignore_knockdown")
    static let fnAimFov       = featureFileName("aim_draw_fov")
    static let fnAimFovVal    = featureFileName("aim_fov_value")
    static let fnNoRecoil     = featureFileName("misc_no_recoil")
    static let fnSpeed        = featureFileName("misc_speed")
    static let fnFastLand     = featureFileName("misc_fast_landing")
    static let fnFastMedkit   = featureFileName("misc_fast_medkit")
    static let fnFastRevive   = featureFileName("misc_fast_revive")

    static var allFeatureFiles: [String] {
        [fnEspEnabled, fnEspLine, fnEspBox, fnEspHealth, fnEspName,
         fnAimEnabled, fnAimType, fnAimTarget, fnAimIgnoreKD, fnAimFov,
         fnAimFovVal, fnNoRecoil, fnSpeed, fnFastLand, fnFastMedkit, fnFastRevive]
    }

    // MARK: - Write feature files to game Documents
    // Each .dat file = XOR-encrypted value (token + hwid tied)
    // bool feature: file exists = on, missing = off
    // value feature: file contains XOR-encrypted value string

    func writeFeatureFiles(to docsPath: String, token: String, hwid: String) {
        let fm = FileManager.default
        let ts = Int(Date().timeIntervalSince1970)
        let expiry = ts + 3600 // 1 hour token

        func writeFile(_ name: String, _ value: String) {
            let path = (docsPath as NSString).appendingPathComponent(name)
            // Content: "value|token|hwid|expiry" XOR-encrypted
            let raw = "\(value)|\(token)|\(hwid)|\(expiry)"
            let encrypted = Data(raw.utf8.map { $0 ^ CheatSettings.xorKey })
            fm.createFile(atPath: path, contents: encrypted)
        }

        func deleteFile(_ name: String) {
            let path = (docsPath as NSString).appendingPathComponent(name)
            try? fm.removeItem(atPath: path)
        }

        // ESP
        espEnabled   ? writeFile(Self.fnEspEnabled, "1")   : deleteFile(Self.fnEspEnabled)
        espLine      ? writeFile(Self.fnEspLine, "1")      : deleteFile(Self.fnEspLine)
        espBox       ? writeFile(Self.fnEspBox, "1")       : deleteFile(Self.fnEspBox)
        espHealth    ? writeFile(Self.fnEspHealth, "1")    : deleteFile(Self.fnEspHealth)
        espName      ? writeFile(Self.fnEspName, "1")      : deleteFile(Self.fnEspName)

        // AIM
        aimEnabled   ? writeFile(Self.fnAimEnabled, aimType.rawValue) : deleteFile(Self.fnAimEnabled)
        writeFile(Self.fnAimTarget,  aimTarget.rawValue)
        writeFile(Self.fnAimIgnoreKD, aimIgnoreKnockdown ? "1" : "0")
        aimDrawFov   ? writeFile(Self.fnAimFov, "1")      : deleteFile(Self.fnAimFov)
        writeFile(Self.fnAimFovVal, String(format: "%.0f", aimFovValue))

        // MISC
        miscNoRecoil   ? writeFile(Self.fnNoRecoil, "1")    : deleteFile(Self.fnNoRecoil)
        miscSpeed      ? writeFile(Self.fnSpeed, "1")        : deleteFile(Self.fnSpeed)
        miscFastLanding ? writeFile(Self.fnFastLand, "1")   : deleteFile(Self.fnFastLand)
        miscFastMedkit  ? writeFile(Self.fnFastMedkit, "1") : deleteFile(Self.fnFastMedkit)
        miscFastRevive  ? writeFile(Self.fnFastRevive, "1") : deleteFile(Self.fnFastRevive)
    }

    // MARK: - Encode to localConfig.json payload (legacy — kept for compatibility)

    func toJSON(token: String, hwid: String) -> Data? {
        let ts = Int(Date().timeIntervalSince1970)
        let expiry = ts + 3600
        let dict: [String: Any] = [
            "testCodePatch":     true,
            "esp_enabled":       espEnabled,
            "esp_line":          espLine,
            "esp_box":           espBox,
            "esp_health":        espHealth,
            "esp_name":          espName,
            "esp_player_count":  espPlayerCount,
            "aim_enabled":       aimEnabled,
            "aim_type":          aimType.rawValue,
            "aim_target":        aimTarget.rawValue,
            "aim_ignore_knockdown": aimIgnoreKnockdown,
            "aim_draw_fov":      aimDrawFov,
            "aim_fov_value":     aimFovValue,
            "misc_no_recoil":    miscNoRecoil,
            "misc_speed":        miscSpeed,
            "misc_fast_landing": miscFastLanding,
            "misc_fast_medkit":  miscFastMedkit,
            "misc_fast_revive":  miscFastRevive,
            "_ffex_token":       token,
            "_ffex_hwid":        hwid,
            "_ffex_ts":          ts,
            "_ffex_exp":         expiry
        ]
        return try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
    }
}
