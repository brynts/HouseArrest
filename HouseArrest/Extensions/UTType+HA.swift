import UniformTypeIdentifiers

extension UTType {
    /// HouseArrest package — dynamic type tagged to `.ha`, conforming to public.data
    /// (same pattern Feather uses for ipa/p12/deb).
    static var haPackage: UTType {
        UTType(filenameExtension: "ha", conformingTo: .data)!
    }
}
