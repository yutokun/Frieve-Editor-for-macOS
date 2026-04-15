#include <metal_stdlib>
using namespace metal;

struct BrowserMetalViewportUniforms {
    float2 viewportSize;
    float2 worldScale;
    float2 worldOffset;
};

struct BrowserMetalColorVertex {
    float2 position;
    float4 color;
};

struct BrowserMetalColorOut {
    float4 position [[position]];
    float4 color;
};

struct BrowserMetalLinkInstance {
    float2 start;
    float2 end;
    float2 control1;
    float2 control2;
    float4 color;
    float lineWidth;
    int shapeIndex;
    float isArrow;
    float curveOffset;
    float3 padding;
};

struct BrowserMetalLinkOut {
    float4 position [[position]];
    float2 localPoint;
    float2 halfSize;
    float4 color;
    float lineWidth;
    float isArrow;
};

struct BrowserMetalTextInstance {
    float2 center;
    float2 size;
    float2 atlasUVOrigin;
    float2 atlasUVSize;
    float4 tintColor;
    float hasTexture;
    float cornerRadius;
    float yPixelOffset;
    float _pad;
};

struct BrowserMetalTextOut {
    float4 position [[position]];
    float2 textureUV;
    float4 tintColor;
    float hasTexture;
};

struct BrowserMetalCardInstance {
    float2 center;
    float2 contentSize;
    float2 paddedSize;
    float2 shadowOffset;
    float2 atlasUVOrigin;
    float2 atlasUVSize;
    float4 fillColor;
    float4 strokeColor;
    float4 glowColor;
    float4 shadowColor;
    float strokeWidth;
    float glowRadius;
    float shadowRadius;
    int shapeIndex;
    float hasTexture;
    float cornerRadius;
    float2 padding;
};

struct BrowserMetalCardOut {
    float4 position [[position]];
    float2 localPoint;
    float2 atlasUVOrigin;
    float2 atlasUVSize;
    float2 contentSize;
    float2 shadowOffset;
    float4 fillColor;
    float4 strokeColor;
    float4 glowColor;
    float4 shadowColor;
    float strokeWidth;
    float glowRadius;
    float shadowRadius;
    int shapeIndex;
    float hasTexture;
    float cornerRadius;
};

static float2 browserViewportTransform(float2 pixelPoint, float2 viewportSize) {
    return float2(
        (pixelPoint.x / max(viewportSize.x, 1.0f)) * 2.0f - 1.0f,
        1.0f - (pixelPoint.y / max(viewportSize.y, 1.0f)) * 2.0f
    );
}

static float2 browserWorldToPixel(float2 worldPoint, constant BrowserMetalViewportUniforms &viewport) {
    return worldPoint * viewport.worldScale + viewport.worldOffset;
}

static float3 browserStraightAlphaRGB(float4 sampled) {
    if (sampled.a <= 0.0001f) {
        return float3(0.0f);
    }
    return clamp(sampled.rgb / sampled.a, 0.0f, 1.0f);
}

vertex BrowserMetalColorOut browserColorVertex(
    const device BrowserMetalColorVertex *vertices [[buffer(0)]],
    constant BrowserMetalViewportUniforms &viewport [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    BrowserMetalColorOut out;
    float2 pixelPoint = vertices[vertexID].position;
    out.position = float4(browserViewportTransform(pixelPoint, viewport.viewportSize), 0.0f, 1.0f);
    out.color = vertices[vertexID].color;
    return out;
}

fragment float4 browserColorFragment(BrowserMetalColorOut in [[stage_in]]) {
    return in.color;
}

static float browserCapsuleDistance(float2 p, float halfLength, float radius) {
    float2 q = float2(abs(p.x) - max(halfLength - radius, 0.0f), abs(p.y));
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - radius;
}

static float browserSignedDistanceEllipse(float2 p, float2 halfSize) {
    float2 safeHalfSize = max(halfSize, float2(0.001f));
    float2 q = abs(p);
    float k0 = length(q / safeHalfSize);
    float k1 = length(q / (safeHalfSize * safeHalfSize));
    return (k0 - 1.0f) * k0 / max(k1, 0.001f);
}

static float browserDistanceSquaredToSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001f), 0.0f, 1.0f);
    float2 d = pa - ba * h;
    return dot(d, d);
}

static float browserSignedDistancePolygon(float2 p, thread const float2 *vertices, int count) {
    float minDistanceSquared = FLT_MAX;
    bool inside = false;
    for (int index = 0, previous = count - 1; index < count; previous = index, index++) {
        float2 a = vertices[previous];
        float2 b = vertices[index];
        minDistanceSquared = min(minDistanceSquared, browserDistanceSquaredToSegment(p, a, b));

        float deltaY = b.y - a.y;
        float safeDeltaY = abs(deltaY) < 0.0001f ? (deltaY >= 0.0f ? 0.0001f : -0.0001f) : deltaY;
        bool intersects = ((a.y > p.y) != (b.y > p.y)) &&
            (p.x < (b.x - a.x) * (p.y - a.y) / safeDeltaY + a.x);
        if (intersects) {
            inside = !inside;
        }
    }
    float distance = sqrt(max(minDistanceSquared, 0.0f));
    return inside ? -distance : distance;
}

vertex BrowserMetalLinkOut browserLinkVertex(
    constant BrowserMetalViewportUniforms &viewport [[buffer(0)]],
    const device BrowserMetalLinkInstance *links [[buffer(1)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };

    BrowserMetalLinkInstance link = links[instanceID];
    float2 start = browserWorldToPixel(link.start, viewport);
    float2 end = browserWorldToPixel(link.end, viewport);
    float2 delta = end - start;
    float segmentLength = max(length(delta), 0.001f);
    float2 direction = delta / segmentLength;
    float2 normal = float2(-direction.y, direction.x);
    float2 corner = corners[vertexID];

    BrowserMetalLinkOut out;
    if (link.isArrow > 0.5f) {
        float forward = max(link.lineWidth * 1.4f, 8.0f);
        float backward = max(link.lineWidth * 0.9f, 5.0f);
        float halfWidth = max(link.lineWidth * 0.72f, 4.0f);
        float2 local = float2(mix(-backward, forward, (corner.x + 1.0f) * 0.5f), corner.y * halfWidth);
        float2 pixelPoint = end + direction * local.x + normal * local.y;
        out.position = float4(browserViewportTransform(pixelPoint, viewport.viewportSize), 0.0f, 1.0f);
        out.localPoint = local;
        out.halfSize = float2(max(forward, backward), halfWidth);
    } else {
        float halfLength = segmentLength * 0.5f + max(link.lineWidth, 2.0f);
        float halfWidth = max(link.lineWidth * 0.5f + 1.0f, 1.5f);
        float2 center = (start + end) * 0.5f;
        float2 local = float2(corner.x * halfLength, corner.y * halfWidth);
        float2 pixelPoint = center + direction * local.x + normal * local.y;
        out.position = float4(browserViewportTransform(pixelPoint, viewport.viewportSize), 0.0f, 1.0f);
        out.localPoint = local;
        out.halfSize = float2(halfLength, halfWidth);
    }
    out.color = link.color;
    out.lineWidth = link.lineWidth;
    out.isArrow = link.isArrow;
    return out;
}

fragment float4 browserLinkFragment(BrowserMetalLinkOut in [[stage_in]]) {
    float alpha = 0.0f;
    if (in.isArrow > 0.5f) {
        float backward = max(in.lineWidth * 0.9f, 5.0f);
        float forward = max(in.lineWidth * 1.4f, 8.0f);
        float halfWidth = in.halfSize.y;
        float x = in.localPoint.x;
        float y = abs(in.localPoint.y);
        float xMin = -backward;
        float xMax = forward;
        float span = max(xMax - xMin, 0.001f);
        float t = clamp((x - xMin) / span, 0.0f, 1.0f);
        float yLimit = (1.0f - t) * halfWidth;
        float edgeDistance = min(min(x - xMin, xMax - x), yLimit - y);
        alpha = smoothstep(-1.0f, 1.0f, edgeDistance);
    } else {
        float radius = max(in.lineWidth * 0.5f, 1.0f);
        float distance = browserCapsuleDistance(in.localPoint, in.halfSize.x, radius);
        alpha = 1.0f - smoothstep(0.0f, 1.2f, distance);
    }
    if (alpha < 0.001f) {
        discard_fragment();
    }
    return float4(in.color.rgb, in.color.a * alpha);
}

vertex BrowserMetalTextOut browserTextVertex(
    constant BrowserMetalViewportUniforms &viewport [[buffer(0)]],
    const device BrowserMetalTextInstance *texts [[buffer(1)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };
    const float2 textureUVs[4] = {
        float2(0.0f, 0.0f),
        float2(1.0f, 0.0f),
        float2(0.0f, 1.0f),
        float2(1.0f, 1.0f)
    };

    BrowserMetalTextInstance text = texts[instanceID];
    float2 offset = corners[vertexID] * (text.size * 0.5f);
    float2 pixelCenter = browserWorldToPixel(text.center, viewport);
    pixelCenter.y += text.yPixelOffset;
    float2 pixelPoint = pixelCenter + offset;

    BrowserMetalTextOut out;
    out.position = float4(browserViewportTransform(pixelPoint, viewport.viewportSize), 0.0f, 1.0f);
    out.textureUV = text.atlasUVOrigin + text.atlasUVSize * textureUVs[vertexID];
    out.tintColor = text.tintColor;
    out.hasTexture = text.hasTexture;
    return out;
}

fragment float4 browserTextFragment(
    BrowserMetalTextOut in [[stage_in]],
    const device BrowserMetalTextInstance *texts [[buffer(0)]],
    texture2d<float> atlasTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    (void)texts;
    if (in.hasTexture < 0.5f) {
        discard_fragment();
    }
    float4 sampled = atlasTexture.sample(textureSampler, in.textureUV);
    float alpha = sampled.a * in.tintColor.a;
    if (alpha < 0.001f) {
        discard_fragment();
    }
    return float4(browserStraightAlphaRGB(sampled) * in.tintColor.rgb, alpha);
}

vertex BrowserMetalCardOut browserCardVertex(
    constant BrowserMetalViewportUniforms &viewport [[buffer(0)]],
    const device BrowserMetalCardInstance *cards [[buffer(1)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };

    BrowserMetalCardInstance card = cards[instanceID];
    BrowserMetalCardOut out;
    float2 offset = corners[vertexID] * (card.paddedSize * 0.5f);
    float2 pixelPoint = browserWorldToPixel(card.center, viewport) + offset;
    out.position = float4(browserViewportTransform(pixelPoint, viewport.viewportSize), 0.0f, 1.0f);
    out.localPoint = offset;
    out.atlasUVOrigin = card.atlasUVOrigin;
    out.atlasUVSize = card.atlasUVSize;
    out.contentSize = card.contentSize;
    out.shadowOffset = card.shadowOffset;
    out.fillColor = card.fillColor;
    out.strokeColor = card.strokeColor;
    out.glowColor = card.glowColor;
    out.shadowColor = card.shadowColor;
    out.strokeWidth = card.strokeWidth;
    out.glowRadius = card.glowRadius;
    out.shadowRadius = card.shadowRadius;
    out.shapeIndex = card.shapeIndex;
    out.hasTexture = card.hasTexture;
    out.cornerRadius = card.cornerRadius;
    return out;
}

static float browserSignedDistanceRect(float2 p, float2 halfSize, float cornerRadius) {
    float2 q = abs(p) - (halfSize - cornerRadius);
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - cornerRadius;
}

static float browserSignedDistanceCircle(float2 p, float2 halfSize) {
    return length(p / max(halfSize, float2(1.0f))) - 1.0f;
}

static float browserSignedDistanceDiamond(float2 p, float2 halfSize) {
    float2 normalized = abs(p) / max(halfSize, float2(1.0f));
    return normalized.x + normalized.y - 1.0f;
}

static float browserSignedDistanceHexagon(float2 p, float2 halfSize) {
    float2 q = abs(p);
    const float k = 0.57735026919f;
    q -= 2.0f * min(dot(float2(k, 1.0f), q), 0.0f) * float2(k, 1.0f);
    q -= float2(clamp(q.x, -k * halfSize.x, k * halfSize.x), halfSize.y);
    return length(q) * sign(q.y);
}

static float browserSignedDistance(float2 p, float2 halfSize, int shapeIndex, float cornerRadius) {
    int normalizedShapeIndex = (shapeIndex % 16 + 16) % 16;
    float minHalf = min(halfSize.x, halfSize.y);
    switch (normalizedShapeIndex) {
        case 0:
        case 1:
            return browserSignedDistanceRect(p, halfSize, 0.0f);
        case 2:
            return browserSignedDistanceRect(p, halfSize, min(cornerRadius, minHalf));
        case 3:
            return browserSignedDistanceRect(p, halfSize, minHalf);
        case 4:
            return browserSignedDistanceEllipse(p, halfSize);
        case 5:
            return browserSignedDistanceDiamond(p, halfSize);
        case 6:
            return browserSignedDistanceHexagon(p, halfSize);
        case 7: {
            float inset = halfSize.y * 0.5f;
            float2 vertices[4] = {
                float2(-halfSize.x + inset, -halfSize.y),
                float2(halfSize.x - inset, -halfSize.y),
                float2(halfSize.x, halfSize.y),
                float2(-halfSize.x, halfSize.y)
            };
            return browserSignedDistancePolygon(p, vertices, 4);
        }
        case 8: {
            float inset = halfSize.y * 0.5f;
            float2 vertices[4] = {
                float2(-halfSize.x, -halfSize.y),
                float2(halfSize.x, -halfSize.y),
                float2(halfSize.x - inset, halfSize.y),
                float2(-halfSize.x + inset, halfSize.y)
            };
            return browserSignedDistancePolygon(p, vertices, 4);
        }
        case 9: {
            float extent = minHalf * 0.56f;
            return browserSignedDistanceRect(p, float2(extent, extent), 0.0f);
        }
        case 10: {
            float radius = minHalf * 0.56f;
            return browserSignedDistanceEllipse(p, float2(radius, radius));
        }
        case 11: {
            float radius = minHalf * 0.64f;
            float2 vertices[3] = {
                float2(0.0f, -radius),
                float2(radius * 0.8660254f, radius * 0.5f),
                float2(-radius * 0.8660254f, radius * 0.5f)
            };
            return browserSignedDistancePolygon(p, vertices, 3);
        }
        case 12: {
            float radius = minHalf * 0.64f;
            float2 vertices[3] = {
                float2(0.0f, radius),
                float2(radius * 0.8660254f, -radius * 0.5f),
                float2(-radius * 0.8660254f, -radius * 0.5f)
            };
            return browserSignedDistancePolygon(p, vertices, 3);
        }
        case 13: {
            float radius = minHalf * 0.64f;
            return browserSignedDistanceDiamond(p, float2(radius, radius));
        }
        case 14: {
            float radius = minHalf * 0.64f;
            float2 vertices[6];
            for (int step = 0; step < 6; step++) {
                float angle = M_PI_F / 6.0f + M_PI_F / 3.0f * step;
                vertices[step] = float2(sin(angle) * radius, -cos(angle) * radius);
            }
            return browserSignedDistancePolygon(p, vertices, 6);
        }
        case 15: {
            float outerRadius = minHalf * 0.68f;
            float innerRadius = outerRadius * 0.38196602f;
            float2 vertices[10];
            for (int step = 0; step < 10; step++) {
                float radius = (step % 2 == 0) ? outerRadius : innerRadius;
                float angle = -M_PI_F / 2.0f + M_PI_F / 5.0f * step;
                vertices[step] = float2(cos(angle) * radius, sin(angle) * radius);
            }
            return browserSignedDistancePolygon(p, vertices, 10);
        }
        default:
            return browserSignedDistanceRect(p, halfSize, min(cornerRadius, minHalf));
    }
}

fragment float4 browserCardFragment(
    BrowserMetalCardOut in [[stage_in]],
    const device BrowserMetalCardInstance *cards [[buffer(0)]],
    texture2d<float> cardTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    (void)cards;
    float2 halfContent = in.contentSize * 0.5f;
    float2 contentPoint = in.localPoint;
    float2 shadowPoint = contentPoint - in.shadowOffset;

    float distance = browserSignedDistance(contentPoint, halfContent, in.shapeIndex, in.cornerRadius);
    float shadowDistance = browserSignedDistance(shadowPoint, halfContent, in.shapeIndex, in.cornerRadius);

    float edgeAA = 0.5f;
    float fillAlpha = 1.0f - smoothstep(-edgeAA, edgeAA, distance);
    float strokeHalfWidth = max(in.strokeWidth * 0.5f, 0.5f);
    float strokeBand = 1.0f - smoothstep(strokeHalfWidth - edgeAA, strokeHalfWidth + edgeAA, abs(distance));
    float glowBand = smoothstep(in.glowRadius + 1.5f, in.glowRadius * 0.35f, abs(distance));
    float shadowAlpha = (1.0f - smoothstep(in.shadowRadius, in.shadowRadius + 6.0f, shadowDistance)) * in.shadowColor.a;

    float4 base = in.fillColor;
    if (in.hasTexture > 0.5f) {
        float2 textureUV = clamp((contentPoint + halfContent) / max(in.contentSize, float2(1.0f)), 0.0f, 1.0f);
        float2 atlasUV = in.atlasUVOrigin + in.atlasUVSize * textureUV;
        float4 sampled = cardTexture.sample(textureSampler, atlasUV);
        base.rgb = mix(in.fillColor.rgb, browserStraightAlphaRGB(sampled), sampled.a);
        base.a = in.fillColor.a;
    }

    float4 color = float4(0.0f);
    color += float4(in.shadowColor.rgb, shadowAlpha);
    color = mix(color, base, fillAlpha);
    color = mix(color, float4(in.glowColor.rgb, max(in.glowColor.a, glowBand * in.glowColor.a)), glowBand);
    color = mix(color, in.strokeColor, strokeBand);

    float alpha = max(max(color.a, fillAlpha * base.a), shadowAlpha);
    if (alpha < 0.001f) {
        discard_fragment();
    }
    return float4(color.rgb, alpha);
}

struct BrowserMetalLabelGroupInstance {
    float2 center;
    float2 halfSize;
    float4 color;
    float strokeWidth;
    float cornerRadius;
    float2 padding;
};

struct BrowserMetalLabelGroupOut {
    float4 position [[position]];
    float2 localPoint;
    float2 halfSize;
    float4 color;
    float strokeWidth;
    float cornerRadius;
};

vertex BrowserMetalLabelGroupOut browserLabelGroupVertex(
    constant BrowserMetalViewportUniforms &viewport [[buffer(0)]],
    const device BrowserMetalLabelGroupInstance *groups [[buffer(1)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const float2 corners[4] = {
        float2(-1.0f, -1.0f),
        float2( 1.0f, -1.0f),
        float2(-1.0f,  1.0f),
        float2( 1.0f,  1.0f)
    };
    BrowserMetalLabelGroupInstance g = groups[instanceID];
    float2 pixelHalfSize = abs(g.halfSize * viewport.worldScale) + g.padding;
    float margin = g.strokeWidth * 0.5f + 1.5f;
    float2 offset = corners[vertexID] * (pixelHalfSize + margin);
    BrowserMetalLabelGroupOut out;
    out.position = float4(browserViewportTransform(browserWorldToPixel(g.center, viewport) + offset, viewport.viewportSize), 0.0f, 1.0f);
    out.localPoint = offset;
    out.halfSize = pixelHalfSize;
    out.color = g.color;
    out.strokeWidth = g.strokeWidth;
    out.cornerRadius = g.cornerRadius;
    return out;
}

fragment float4 browserLabelGroupFragment(BrowserMetalLabelGroupOut in [[stage_in]]) {
    float dist;
    if (in.cornerRadius < -1.5f) {
        dist = browserSignedDistanceCircle(in.localPoint, in.halfSize) * min(in.halfSize.x, in.halfSize.y);
    } else if (in.cornerRadius < 0.0f) {
        dist = length(in.localPoint) - min(in.halfSize.x, in.halfSize.y);
    } else {
        float2 q = abs(in.localPoint) - (in.halfSize - in.cornerRadius);
        dist = length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - in.cornerRadius;
    }
    float borderDist = abs(dist) - in.strokeWidth * 0.5f;
    float alpha = (1.0f - smoothstep(-0.5f, 0.5f, borderDist)) * in.color.a;
    if (alpha < 0.001f) discard_fragment();
    return float4(in.color.rgb, alpha);
}
