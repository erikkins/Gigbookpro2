import Foundation
import DataCompression

/// Helper for gzip decompression using DataCompression library
enum GzipHelper {
    
    enum GzipError: Error, LocalizedError {
        case decompressionFailed
        
        var errorDescription: String? {
            return "Gzip decompression failed"
        }
    }
    
    /// Decompress gzip data
    static func decompress(_ data: Data) throws -> Data {
        guard let decompressed = data.gunzip() else {
            throw GzipError.decompressionFailed
        }
        print("✅ GzipHelper: \(data.count) → \(decompressed.count) bytes")
        return decompressed
    }
}
