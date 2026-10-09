import AppKit
import MetalKit

final class Settings {
    var speed: Float = 1
    var grain: Float = 1
    var brightness: Float = 1
    var isDarkMode = true
    var paused = false
}

struct Uniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var grain: Float
    var brightness: Float
    var darkMode: Float
    var fieldResolution: SIMD2<Float> = .zero
}

final class FlameRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let fieldPipeline: MTLRenderPipelineState
    let compositePipeline: MTLRenderPipelineState
    let settings: Settings
    let reference: Bool
    private var fieldTexture: MTLTexture?
    private var lastFrame = CACurrentMediaTime()
    private var elapsed: Float = 0
    private let inFlight = DispatchSemaphore(value: 3)

    init(settings: Settings, reference: Bool = false) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "SimplexFlame", code: 1, userInfo: [NSLocalizedDescriptionKey: "A Metal-compatible GPU is required."])
        }
        self.device = device
        self.queue = queue
        self.settings = settings
        self.reference = reference
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let url = resources.url(forResource: "Flame", withExtension: "metal") else {
            throw NSError(domain: "SimplexFlame", code: 2, userInfo: [NSLocalizedDescriptionKey: "Flame.metal is missing from the app resources."])
        }
        let source = try String(contentsOf: url)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "flameFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "compositeFragment")
        compositePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "fieldFragment")
        descriptor.colorAttachments[0].pixelFormat = .r32Float
        fieldPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    func makeView(frame: NSRect) -> MTKView {
        let view = MTKView(frame: frame, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.preferredFramesPerSecond = 30
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        view.delegate = self
        resize(view)
        return view
    }

    // Match the current screen's full backing resolution, including Retina scale.
    func resize(_ view: MTKView) {
        let backing = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        view.drawableSize = CGSize(width: max(1,(view.bounds.width*backing).rounded()), height: max(1,(view.bounds.height*backing).rounded()))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let delta = min(now-lastFrame,0.1)
        lastFrame = now
        if !settings.paused { elapsed += Float(delta)*settings.speed }
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        encode(command, pass: pass, size: view.drawableSize, time: elapsed)
        command.present(drawable)
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.commit()
    }

    private func encode(_ command: MTLCommandBuffer, pass: MTLRenderPassDescriptor, size: CGSize, time: Float) {
        var uniforms = Uniforms(resolution: SIMD2(Float(size.width),Float(size.height)), time: time, grain: settings.grain, brightness: settings.brightness, darkMode: settings.isDarkMode ? 1 : 0)
        var sampledField: MTLTexture?
        if !reference {
            let width = Int(ceil(size.width/4))+2, height = Int(ceil(size.height/4))+2
            if fieldTexture?.width != width || fieldTexture?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = [.renderTarget,.shaderRead]
                fieldTexture = device.makeTexture(descriptor: descriptor)
                fieldTexture?.label = "Quarter-size smooth flame field"
            }
            if let texture = fieldTexture {
                uniforms.fieldResolution = SIMD2(Float(width),Float(height))
                let fieldPass = MTLRenderPassDescriptor()
                fieldPass.colorAttachments[0].texture = texture
                fieldPass.colorAttachments[0].loadAction = .dontCare
                fieldPass.colorAttachments[0].storeAction = .store
                if let encoder = command.makeRenderCommandEncoder(descriptor: fieldPass) {
                    encoder.label = "Flame shape (1/16 pixel count)"
                    encoder.setRenderPipelineState(fieldPipeline)
                    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    encoder.endEncoding()
                    sampledField = texture
                }
            }
        }
        // Full-screen triangle overwrites every pixel, so no clear is necessary.
        pass.colorAttachments[0].loadAction = .dontCare
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = sampledField == nil ? "Reference flame" : "Full-resolution palette and grain"
        encoder.setRenderPipelineState(sampledField == nil ? pipeline : compositePipeline)
        if let texture = sampledField { encoder.setFragmentTexture(texture,index: 0) }
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    func benchmark() throws {
        var sizes = [(1512,1000),(2160,1440)]
        for screen in NSScreen.screens {
            let width = Int(screen.frame.width*screen.backingScaleFactor)
            let height = Int(screen.frame.height*screen.backingScaleFactor)
            if !sizes.contains(where: { $0.0 == width && $0.1 == height }) { sizes.append((width,height)) }
        }
        for (width,height) in sizes {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,width: width,height: height,mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget]
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw CocoaError(.fileWriteUnknown) }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].storeAction = .store
            var durations: [Double] = []
            for frame in 0..<132 {
                guard let command = queue.makeCommandBuffer() else { throw CocoaError(.fileWriteUnknown) }
                encode(command,pass: pass,size: CGSize(width: width,height: height),time: Float(frame)/30)
                command.commit()
                command.waitUntilCompleted()
                if let error = command.error { throw error }
                if frame >= 12 {
                    let milliseconds = (command.gpuEndTime-command.gpuStartTime)*1000
                    guard milliseconds > 0 else { throw NSError(domain: "SimplexFlame",code: 3,userInfo: [NSLocalizedDescriptionKey:"GPU timestamps unavailable."]) }
                    durations.append(milliseconds)
                }
            }
            durations.sort()
            print(String(format:"%@ %dx%d: median %.3f ms, p95 %.3f ms GPU/frame (%@, 120 samples)",reference ? "reference" : "optimized",width,height,durations[durations.count/2],durations[Int(Double(durations.count)*0.95)],device.name))
        }
    }

    func snapshot(path: String, time: Float, width: Int = 1512, height: Int = 1000) throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer() else { throw CocoaError(.fileWriteUnknown) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        encode(command, pass: pass, size: CGSize(width: width,height: height), time: time)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        texture.getBytes(&bytes, bytesPerRow: width*4, from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: [.byteOrder32Little,CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)], provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: URL(fileURLWithPath: path))
        print("Rendered \(path) at t=\(time) on \(device.name)")
    }
}
