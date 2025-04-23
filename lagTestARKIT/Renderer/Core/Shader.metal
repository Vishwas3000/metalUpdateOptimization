//
//  Shader.metal
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Rectangle vertex structure for image tracking
typedef struct {
    float3 position [[attribute(VertexAttributePosition)]];
    float4 color [[attribute(VertexAttributeTexcoord)]]; // Reusing TexCoord attribute index for color
} RectangleVertexIn;

// Vertex output structure
typedef struct {
    float4 position [[position]];
    float4 color;
} RectangleVertexOut;

vertex RectangleVertexOut
imageTrackingVertexShader(RectangleVertexIn in [[stage_in]],
                          constant SharedUniforms &uniforms [[buffer(BufferIndexSharedUniforms)]],
                          constant float4x4 &modelMatrix [[buffer(BufferIndexInstanceUniforms)]],
                          constant float4 &vertexColor [[buffer(BufferIndexMeshGenerics)]]) {
    RectangleVertexOut out;
    
    // Calculate vertex position
    float4 position = float4(in.position, 1.0);
    float4 worldPosition = modelMatrix * position;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    
    // Use the uniform color passed from Swift
    out.color = vertexColor;
    
    return out;
}

// Fragment shader for image tracking rectangles
// The fragment shader remains the same as before
fragment float4
imageTrackingFragmentShader(RectangleVertexOut in [[stage_in]]) {
    // Simply output the interpolated color
    return in.color;
}
