//
//  BaseRenderer.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit

/// The base renderer protocol that all specialized renderers must implement
protocol Renderer: AnyObject {
    var id: String { get }
    var isEnabled: Bool { get set }
    var renderOrder: Int { get set }
    
    func setup(device: MTLDevice, library: MTLLibrary)
    func update(frame: ARFrame?)
    func draw(renderEncoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer, uniformBufferOffset: Int)
    func resize(size: CGSize)
}

/// Common configuration for renderers
class RendererConfig {
    let device: MTLDevice
    let pixelFormat: MTLPixelFormat
    let depthStencilFormat: MTLPixelFormat
    let sampleCount: Int
    
    init(device: MTLDevice,
         pixelFormat: MTLPixelFormat = .bgra8Unorm,
         depthStencilFormat: MTLPixelFormat = .depth32Float_stencil8,
         sampleCount: Int = 1) {
        self.device = device
        self.pixelFormat = pixelFormat
        self.depthStencilFormat = depthStencilFormat
        self.sampleCount = sampleCount
    }
}

/// Base renderer class that implements common functionality
class BaseRenderer: Renderer {
    let id: String
    var isEnabled: Bool = true
    var renderOrder: Int
    
    let config: RendererConfig
    var pipelineStates: [String: MTLRenderPipelineState] = [:]
    var depthStencilStates: [String: MTLDepthStencilState] = [:]
    var vertexBuffers: [String: MTLBuffer] = [:]
    var indexBuffers: [String: MTLBuffer] = [:]
    var textures: [String: MTLTexture] = [:]
    
    private var viewportSize: CGSize = .zero
    
    init(id: String, config: RendererConfig, renderOrder: Int) {
        self.id = id
        self.renderOrder = renderOrder
        self.config = config
    }
    
    func setup(device: MTLDevice, library: MTLLibrary) {
        // Should be overridden by subclasses
    }
    
    func update(frame: ARFrame?) {
        // Should be overridden by subclasses
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, uniformBuffer: MTLBuffer, uniformBufferOffset: Int) {
        // Should be overridden by subclasses
    }
    
    func resize(size: CGSize) {
        viewportSize = size
    }
    
    // Utility methods for subclasses
    
    func createRenderPipelineState(vertexFunction: String, fragmentFunction: String, label: String) -> MTLRenderPipelineState? {
        guard let device = config.device as? MTLDevice,
              let library = device.makeDefaultLibrary(),
              let vertexFunc = library.makeFunction(name: vertexFunction),
              let fragmentFunc = library.makeFunction(name: fragmentFunction) else {
            print("Failed to create shader functions for pipeline: \(label)")
            return nil
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = label
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = config.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = config.depthStencilFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = config.depthStencilFormat
        
        do {
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            pipelineStates[label] = pipelineState
            return pipelineState
        } catch {
            print("Failed to create render pipeline state: \(error)")
            return nil
        }
    }
    
    func createDepthStencilState(compareFunction: MTLCompareFunction = .less,
                                 isWriteEnabled: Bool = true,
                                 label: String) -> MTLDepthStencilState? {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = compareFunction
        depthDescriptor.isDepthWriteEnabled = isWriteEnabled
        
        guard let device = config.device as? MTLDevice else {
            return nil
        }
        
        let state = device.makeDepthStencilState(descriptor: depthDescriptor)
        depthStencilStates[label] = state
        return state
    }
    
    func createStencilState(compareFunction: MTLCompareFunction = .always,
                           writeEnabled: Bool = true,
                           readMask: UInt32 = 0xFF,
                           writeMask: UInt32 = 0xFF,
                           stencilFailOperation: MTLStencilOperation = .keep,
                           depthFailOperation: MTLStencilOperation = .keep,
                           passOperation: MTLStencilOperation = .keep,
                           label: String) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = writeEnabled
        
        let stencil = MTLStencilDescriptor()
        stencil.stencilCompareFunction = compareFunction
        stencil.stencilFailureOperation = stencilFailOperation
        stencil.depthFailureOperation = depthFailOperation
        stencil.depthStencilPassOperation = passOperation
        stencil.readMask = readMask
        stencil.writeMask = writeMask
        
        descriptor.frontFaceStencil = stencil
        descriptor.backFaceStencil = stencil
        
        guard let device = config.device as? MTLDevice else {
            return nil
        }
        
        let state = device.makeDepthStencilState(descriptor: descriptor)
        depthStencilStates[label] = state
        return state
    }
    
    func createVertexBuffer(vertices: [Float], label: String) -> MTLBuffer? {
        guard let device = config.device as? MTLDevice else {
            return nil
        }
        
        let vertexDataSize = vertices.count * MemoryLayout<Float>.size
        guard let buffer = device.makeBuffer(bytes: vertices, length: vertexDataSize, options: .storageModeShared) else {
            return nil
        }
        
        buffer.label = label
        vertexBuffers[label] = buffer
        return buffer
    }
    
    func createIndexBuffer(indices: [UInt16], label: String) -> MTLBuffer? {
        guard let device = config.device as? MTLDevice else {
            return nil
        }
        
        let indexDataSize = indices.count * MemoryLayout<UInt16>.size
        guard let buffer = device.makeBuffer(bytes: indices, length: indexDataSize, options: .storageModeShared) else {
            return nil
        }
        
        buffer.label = label
        indexBuffers[label] = buffer
        return buffer
    }
}

/// Manages render passes between multiple renderers
class RenderCoordinator {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderers: [Renderer] = []
    
    // Shared buffers
    private var sharedUniformBuffer: MTLBuffer
    private var instanceUniformBuffer: MTLBuffer
    private var uniformBufferIndex: Int = 0
    
    private let kMaxBuffersInFlight = 3
    private let kAlignedSharedUniformsSize: Int
    private let kAlignedInstanceUniformsSize: Int
    private let kMaxAnchorInstanceCount = 64
    
    init(device: MTLDevice) {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        commandQueue = queue
        
        // Calculate buffer sizes with alignment
        kAlignedSharedUniformsSize = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
        kAlignedInstanceUniformsSize = ((MemoryLayout<InstanceUniforms>.size * kMaxAnchorInstanceCount) & ~0xFF) + 0x100
        
        // Create uniform buffers
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        let instanceUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        
        guard let sharedBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared),
              let instanceBuffer = device.makeBuffer(length: instanceUniformBufferSize, options: .storageModeShared) else {
            fatalError("Failed to create uniform buffers")
        }
        
        sharedUniformBuffer = sharedBuffer
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        instanceUniformBuffer = instanceBuffer
        instanceUniformBuffer.label = "InstanceUniformBuffer"
    }
    
    func addRenderer(_ renderer: Renderer) {
        renderers.append(renderer)
    }
    
    func removeRenderer(id: String) {
        renderers.removeAll { $0.id == id }
    }
    
    func update(frame: ARFrame) {
        // Update buffer offsets for the current frame
        updateBufferState()
        
        // Update all renderers
        for renderer in renderers where renderer.isEnabled {
            renderer.update(frame: frame)
        }
        
        // Update shared uniforms
        updateSharedUniforms(frame: frame)
    }
    
    func draw(renderDestination: RenderDestinationProvider) {
        guard let renderPassDescriptor = renderDestination.currentRenderPassDescriptor,
              let drawable = renderDestination.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        commandBuffer.label = "RenderPass"
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.label = "MainRenderEncoder"
        
        // Draw with each renderer in order
        for renderer in renderers where renderer.isEnabled {
            renderer.draw(renderEncoder: renderEncoder,
                          uniformBuffer: sharedUniformBuffer,
                          uniformBufferOffset: sharedUniformBufferOffset)
        }
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func resize(size: CGSize) {
        for renderer in renderers {
            renderer.resize(size: size)
        }
    }
    
    // MARK: - Private Methods
    
    private var sharedUniformBufferOffset: Int = 0
    private var instanceUniformBufferOffset: Int = 0
    
    private func updateBufferState() {
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        instanceUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
    }
    
    private func updateSharedUniforms(frame: ARFrame) {
        let uniforms = sharedUniformBuffer.contents()
            .advanced(by: sharedUniformBufferOffset)
            .assumingMemoryBound(to: SharedUniforms.self)
        
        // Update view and projection matrices
        uniforms.pointee.viewMatrix = frame.camera.viewMatrix(for: .portrait)
        uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(for: .portrait,
                                                                          viewportSize: CGSize(width: frame.camera.imageResolution.width,
                                                                                              height: frame.camera.imageResolution.height),
                                                                          zNear: 0.001,
                                                                          zFar: 1000)
        
        // Update lighting based on ARFrame light estimate
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        let directionalLightDirection = simd_normalize(vector3(0.0, 0.0, -1.0))
//        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
    }
}
