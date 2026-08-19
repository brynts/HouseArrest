import Foundation
import zlib

enum ZipUtil {
    static func zip(paths: [String], to dest: String, password: String?) throws {
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }
        FileManager.default.createFile(atPath: dest, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: dest))
        defer { try? handle.close() }

        var centrals: [Data] = []
        var offset: UInt32 = 0
        let pwd = password.flatMap { $0.isEmpty ? nil : $0 }

        for path in paths {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                for file in try walk(path) {
                    let rel = relative(from: (path as NSString).deletingLastPathComponent, to: file)
                    offset += try writeFile(file, name: rel, handle: handle, password: pwd, centrals: &centrals, offset: offset)
                }
            } else {
                offset += try writeFile(
                    path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    handle: handle,
                    password: pwd,
                    centrals: &centrals,
                    offset: offset
                )
            }
        }

        let centralStart = offset
        var centralSize: UInt32 = 0
        for entry in centrals {
            handle.write(entry)
            centralSize += UInt32(entry.count)
        }
        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06, 0, 0, 0, 0])
        appendU16(&eocd, UInt16(centrals.count))
        appendU16(&eocd, UInt16(centrals.count))
        appendU32(&eocd, centralSize)
        appendU32(&eocd, centralStart)
        appendU16(&eocd, 0)
        handle.write(eocd)
    }

    static func unzip(file: String, to folder: String, password: String?) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        var i = 0
        let pwd = password.flatMap { $0.isEmpty ? nil : $0 }
        while i + 30 <= data.count {
            let sig = u32(data, i)
            if sig == 0x02014b50 || sig == 0x06054b50 { break }
            guard sig == 0x04034b50 else { throw PatchError.invalidPackage }
            let flags = u16(data, i + 6)
            let method = u16(data, i + 8)
            let compSize = Int(u32(data, i + 18))
            let nameLen = Int(u16(data, i + 26))
            let extraLen = Int(u16(data, i + 28))
            let nameStart = i + 30
            let nameEnd = nameStart + nameLen
            guard nameEnd + extraLen <= data.count else { throw PatchError.invalidPackage }
            let name = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? "file"
            let payloadStart = nameEnd + extraLen
            guard payloadStart + compSize <= data.count else { throw PatchError.invalidPackage }
            var payload = Data(data[payloadStart..<(payloadStart + compSize)])
            if flags & 1 != 0 {
                guard let pwd else { throw PatchError.invalidPackage }
                payload = try ZipCrypto.decrypt(payload, password: pwd)
            }
            let dest = URL(fileURLWithPath: folder).appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                let output: Data
                if method == 0 {
                    output = payload
                } else if method == 8 {
                    output = try inflate(payload)
                } else {
                    throw PatchError.invalidPackage
                }
                try output.write(to: dest, options: .atomic)
            }
            i = payloadStart + compSize
        }
    }

    static func isZip(_ name: String) -> Bool {
        (name as NSString).pathExtension.lowercased() == "zip"
    }

    private static func writeFile(
        _ path: String,
        name: String,
        handle: FileHandle,
        password: String?,
        centrals: inout [Data],
        offset: UInt32
    ) throws -> UInt32 {
        let raw = try Data(contentsOf: URL(fileURLWithPath: path))
        let crc = crc32Value(raw)
        var payload = raw
        var flags: UInt16 = 0
        if let password {
            flags = 1
            payload = ZipCrypto.encrypt(raw, password: password)
        }
        let nameData = Data(name.utf8)
        var local = Data()
        local.append(contentsOf: [0x50, 0x4b, 0x03, 0x04, 20, 0])
        appendU16(&local, flags)
        appendU16(&local, 0)
        appendU16(&local, 0)
        appendU16(&local, 0)
        appendU32(&local, crc)
        appendU32(&local, UInt32(payload.count))
        appendU32(&local, UInt32(raw.count))
        appendU16(&local, UInt16(nameData.count))
        appendU16(&local, 0)
        local.append(nameData)
        handle.write(local)
        handle.write(payload)

        var central = Data()
        central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02, 20, 0, 20, 0])
        appendU16(&central, flags)
        appendU16(&central, 0)
        appendU16(&central, 0)
        appendU16(&central, 0)
        appendU32(&central, crc)
        appendU32(&central, UInt32(payload.count))
        appendU32(&central, UInt32(raw.count))
        appendU16(&central, UInt16(nameData.count))
        appendU16(&central, 0)
        appendU16(&central, 0)
        appendU16(&central, 0)
        appendU16(&central, 0)
        appendU32(&central, 0)
        appendU32(&central, offset)
        central.append(nameData)
        centrals.append(central)
        return UInt32(local.count + payload.count)
    }

    private static func walk(_ folder: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return [] }
        var files: [String] = []
        for case let name as String in enumerator {
            let full = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                files.append(full)
            }
        }
        return files
    }

    private static func relative(from root: String, to path: String) -> String {
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func crc32Value(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress
            return UInt32(crc32(0, ptr, uInt(data.count)))
        }
    }

    private static func inflate(_ source: Data) throws -> Data {
        var payload = source
        var stream = z_stream()
        let initStatus = payload.withUnsafeMutableBytes { buf -> Int32 in
            stream.next_in = buf.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(payload.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initStatus == Z_OK else { throw PatchError.invalidPackage }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var status: Int32
        repeat {
            status = buffer.withUnsafeMutableBytes { outBuf in
                stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(buffer.count)
                return inflate(&stream, Z_NO_FLUSH)
            }
            let have = buffer.count - Int(stream.avail_out)
            if have > 0 {
                output.append(contentsOf: buffer.prefix(have))
            }
        } while status == Z_OK
        guard status == Z_STREAM_END else { throw PatchError.invalidPackage }
        return output
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private enum ZipCrypto {
    static func encrypt(_ data: Data, password: String) -> Data {
        var keys = Keys(password: password)
        var out = Data()
        var header = Data((0..<11).map { _ in UInt8.random(in: 0...255) })
        header.append(0)
        for byte in header { out.append(keys.encode(byte)) }
        for byte in data { out.append(keys.encode(byte)) }
        return out
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard data.count >= 12 else { throw PatchError.invalidPackage }
        var keys = Keys(password: password)
        var rest = Array(data)
        for i in 0..<12 { rest[i] = keys.decode(rest[i]) }
        return Data(rest.dropFirst(12).map { keys.decode($0) })
    }

    private struct Keys {
        var k0: UInt32 = 305419896
        var k1: UInt32 = 591751049
        var k2: UInt32 = 878082192

        init(password: String) {
            for byte in password.utf8 { update(byte) }
        }

        mutating func encode(_ c: UInt8) -> UInt8 {
            let t = c &+ stream()
            update(c)
            return t
        }

        mutating func decode(_ c: UInt8) -> UInt8 {
            let t = c &- stream()
            update(t)
            return t
        }

        mutating func update(_ c: UInt8) {
            k0 = crc(k0, c)
            k1 = (k1 &+ (k0 & 0xff)) &* 134775813 &+ 1
            k2 = crc(k2, UInt8((k1 >> 24) & 0xff))
        }

        func stream() -> UInt8 {
            let temp = k2 | 2
            return UInt8(((temp &* (temp ^ 1)) >> 8) & 0xff)
        }

        func crc(_ value: UInt32, _ c: UInt8) -> UInt32 {
            var byte = c
            return withUnsafePointer(to: &byte) { ptr in
                UInt32(crc32(uLong(value), ptr, 1))
            }
        }
    }
}
