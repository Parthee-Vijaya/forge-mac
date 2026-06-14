import Foundation

/// One action parsed from a model artifact. The skeleton supports whole-file
/// writes only; `line-replace` is reserved for strong models (rejected by the
/// parser for now).
public enum ForgeAction: Sendable, Equatable {
    case file(path: String, contents: String)
    case shell(command: String)
    case start(command: String)
    case addDependency(package: String)
}
