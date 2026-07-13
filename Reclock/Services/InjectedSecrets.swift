/// Build-time configuration. The repo copy is intentionally empty: the TestFlight
/// workflow overwrites this file with real values just before archiving, so secrets
/// never live in git while release builds still carry what they need. Readers fall
/// back to Info.plist so local developers can inject values with INFOPLIST_KEY_
/// overrides instead of editing this file.
enum InjectedSecrets {
    static let aeroDataBoxKey = ""
    static let googleClientID = ""
}
