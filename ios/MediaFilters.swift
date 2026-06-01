import CoreImage
import CoreImage.CIFilterBuiltins

class MediaFilters {
    /// Applies a custom filter to a CIImage
    static func applyFilter(to image: CIImage, filterName: String?) -> CIImage {
        guard let filterName = filterName else { return image }
        
        switch filterName {
        case "bw":
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage ?? image
            
        case "vintage":
            let filter = CIFilter.photoEffectTransfer()
            filter.inputImage = image
            return filter.outputImage ?? image
            
        case "bright_pink":
            // 1. Boost brightness and contrast slightly
            let colorControl = CIFilter.colorControls()
            colorControl.inputImage = image
            colorControl.brightness = 0.05
            colorControl.saturation = 1.15
            colorControl.contrast = 1.05
            
            guard let enhancedImage = colorControl.outputImage else { return image }
            
            // 2. Apply pinkish/rosy tint using CIColorMatrix
            // We boost Red and Blue channels slightly
            let matrixFilter = CIFilter.colorMatrix()
            matrixFilter.inputImage = enhancedImage
            matrixFilter.rVector = CIVector(x: 1.1, y: 0, z: 0, w: 0)
            matrixFilter.gVector = CIVector(x: 0, y: 1.0, z: 0, w: 0)
            matrixFilter.bVector = CIVector(x: 0, y: 0, z: 1.1, w: 0)
            matrixFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            // Optional bias
            matrixFilter.biasVector = CIVector(x: 0.02, y: 0.0, z: 0.02, w: 0)
            
            return matrixFilter.outputImage ?? enhancedImage
            
        default:
            return image
        }
    }
}
import Foundation
import UIKit
import CoreImage

extension MediaFilters {
    
    static func createColorCubeData(from lutImage: UIImage, dimension: Int) -> Data? {
        guard let cgImage = lutImage.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let columnNum = width / dimension
        
        guard width == height, width % dimension == 0 else { return nil }
        
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let dataSize = width * height * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: dataSize)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var cubeData = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        var offset = 0
        
        for z in 0..<dimension {
            let row = z / columnNum
            let col = z % columnNum
            for y in 0..<dimension {
                for x in 0..<dimension {
                    let dataOffset = (row * dimension + y) * width * 4 + (col * dimension + x) * 4
                    let r = Float(pixels[dataOffset]) / 255.0
                    let g = Float(pixels[dataOffset + 1]) / 255.0
                    let b = Float(pixels[dataOffset + 2]) / 255.0
                    let a = Float(pixels[dataOffset + 3]) / 255.0
                    
                    cubeData[offset] = r
                    cubeData[offset + 1] = g
                    cubeData[offset + 2] = b
                    cubeData[offset + 3] = a
                    offset += 4
                }
            }
        }
        
        return cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static var cachedCubes: [String: CIFilter] = [:]

    static func applyLUT(to image: CIImage, lutUri: String) -> CIImage {
        if let cached = cachedCubes[lutUri] {
            cached.setValue(image, forKey: kCIInputImageKey)
            return cached.outputImage ?? image
        }
        
        let cleanedUri = lutUri.replacingOccurrences(of: "file://", with: "")
        
        var lutImage: UIImage?
        if cleanedUri.hasPrefix("http") {
            if let url = URL(string: cleanedUri), let data = try? Data(contentsOf: url) {
                lutImage = UIImage(data: data)
            }
        } else {
            lutImage = UIImage(contentsOfFile: cleanedUri)
        }
        
        guard let validLutImage = lutImage else { return image }
        
        let dimension = 64
        guard let cubeData = createColorCubeData(from: validLutImage, dimension: dimension) else { return image }
        
        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        
        cachedCubes[lutUri] = filter
        
        let toSRGB = CIFilter(name: "CILinearToSRGBToneCurve")
        toSRGB?.setValue(image, forKey: kCIInputImageKey)
        let srgbImage = toSRGB?.outputImage ?? image
        
        filter.setValue(srgbImage, forKey: kCIInputImageKey)
        let filteredImage = filter.outputImage ?? srgbImage
        
        let toLinear = CIFilter(name: "CISRGBToneCurveToLinear")
        toLinear?.setValue(filteredImage, forKey: kCIInputImageKey)
        
        return toLinear?.outputImage ?? filteredImage
    }
}
