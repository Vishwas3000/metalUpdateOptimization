//
//  ShaderTypes.h
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

//
//  ShaderTypes.h
//  ARRenderingEngine
//
//  Common header with definitions needed for both Swift and Metal shaders
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// Buffer indices
typedef enum {
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexSharedUniforms = 2,
    BufferIndexInstanceUniforms = 3
} BufferIndex;

// Texture indices
typedef enum {
    TextureIndexY = 0,
    TextureIndexCbCr = 1,
    TextureIndexMask = 8
} TextureIndex;

// Vertex attribute indices
typedef enum {
    VertexAttributePosition = 0,
    VertexAttributeTexcoord = 1,
    VertexAttributeNormal = 2
} VertexAttribute;

// Shared uniforms - must match structure in Swift
typedef struct {
    // Camera matrices
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
    
    // Lighting properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
    float materialShininess;
    
    // Extra parameters
    float time;
    float _pad[3];
} SharedUniforms;

// Instance uniforms - must match structure in Swift
typedef struct {
    matrix_float4x4 modelMatrix;
} InstanceUniforms;

// Layer uniforms - must match structure in Swift
typedef struct {
    matrix_float4x4 transform;
    float scale;
    float depth;
    int mode;
    float _pad;
} LayerUniforms;

// Shadow uniforms - must match structure in Swift
typedef struct {
    matrix_float4x4 lightViewMatrix;
    matrix_float4x4 lightProjectionMatrix;
    float shadowBias;
} ShadowUniforms;

// Vertex structure - must match structure in Swift
typedef struct {
    vector_float3 position;
    vector_float2 texCoord;
    uint32_t textureIndex;
} Vertex;

#endif /* ShaderTypes_h */
