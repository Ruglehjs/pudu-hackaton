-- shaders.lua
-- Safe HD-2D GLSL shaders for Pudu Fantasy (LOVE2D 11.5 / LuaJIT).
-- Exports:
--   Shaders.MAX_LIGHTS
--   Shaders.load()
--   Shaders.hasUniform(shaderSetOrShader, shaderNameOrUniform, maybeUniform)
--   Shaders.safeSend(shader, uniform, ...)
--   Shaders.send(shaderSet, shaderName, uniform, ...)
--   Shaders.getWarnings(shaderSet)

local Shaders = {}

Shaders.MAX_LIGHTS = 10

-- Weak-keyed cache mapping LOVE Shader userdata -> { [uniformName] = boolean }.
local uniformCacheByShader = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
-- GLSL Shader Sources (LOVE2D 11.5 cross-driver GLSL)
--------------------------------------------------------------------------------

local LIT_SHADER_CODE = [[
extern Image normalMap;
extern number hasNormalMap;
extern number normalStrength;
extern number spriteAngle;
extern number spriteBillboard;
extern number surfaceBaseY;
extern vec3 ambientColor;
extern vec3 sunDir;
extern vec3 sunColor;
extern number sunEnergy;
extern number specStrength;
extern number emissiveBoost;
extern vec3 emissiveColor;
extern vec2 screenSize;
extern number numLights;
extern vec4 lightPosRadius[10];
extern vec4 lightColorEnergy[10];

vec3 safeNormalize(vec3 v, vec3 fallback) {
    float lenSq = dot(v, v);
    if (lenSq < 0.000001) {
        return fallback;
    }
    return v * inversesqrt(lenSq);
}

float compressShoulder(float c) {
    if (c > 0.92) {
        return 0.92 + 0.08 * (1.0 - exp(-(c - 0.92) / 0.28));
    }
    return max(c, 0.0);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 texel = Texel(tex, tc);
    float outAlpha = texel.a * color.a;
    if (outAlpha < 0.004) {
        return vec4(0.0);
    }

    vec3 albedo = texel.rgb * color.rgb;

    // Normal map unpacking (rotated by spriteAngle) or flat (0,0,1) in Modo B.
    vec3 N = vec3(0.0, 0.0, 1.0);
    if (hasNormalMap > 0.5) {
        vec3 nm = Texel(normalMap, tc).rgb * 2.0 - 1.0;
        float str = max(normalStrength, 0.0);
        nm.xy *= str;
        float ca = cos(spriteAngle);
        float sa = sin(spriteAngle);
        vec2 rotXY = vec2(nm.x * ca - nm.y * sa, nm.x * sa + nm.y * ca);
        N = safeNormalize(vec3(rotXY, max(nm.z, 0.05)), vec3(0.0, 0.0, 1.0));
    }

    // Hemispheric ambient with subtle warm/cool variation and light vertical sky lift.
    float hemiT = clamp(N.y * -0.5 + 0.5, 0.0, 1.0);
    vec3 hemiTint = mix(vec3(0.985, 0.970, 0.955), vec3(1.010, 1.018, 1.032), hemiT);
    float screenY = clamp(sc.y / max(screenSize.y, 1.0), 0.0, 1.0);
    float skyGrad = 1.0 + (0.5 - screenY) * 0.04;
    vec3 hemiAmbient = ambientColor * hemiTint * (0.90 + 0.14 * hemiT) * skyGrad;

    // Directional sun with painterly wrapped diffuse + Blinn-Phong specular.
    vec3 L = safeNormalize(sunDir, vec3(-0.45, -0.58, 0.68));
    float energy = max(sunEnergy, 0.0);
    float ndl = clamp((dot(N, L) + 0.38) / 1.38, 0.0, 1.0);

    vec3 H = safeNormalize(L + vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 1.0));
    float ndh = max(dot(N, H), 0.0);
    float spec = (ndh > 0.0001) ? (pow(ndh, 20.0) * max(specStrength, 0.0) * energy) : 0.0;

    // Billboard rim glow + gentle top sun lift (preserves dark pixel-art outlines).
    vec3 rimGlow = vec3(0.0);
    if (spriteBillboard > 0.5) {
        float edge = max(1.0 - max(N.z, 0.0), 0.0);
        float rimCurve = (edge > 0.0001) ? (pow(edge, 2.2) * 0.55) : 0.0;
        float topLift = (1.0 - clamp(tc.y, 0.0, 1.0)) * 0.07;
        float outlineMask = smoothstep(0.04, 0.20, max(albedo.r, max(albedo.g, albedo.b)));
        rimGlow = sunColor * energy * (rimCurve + topLift) * 0.35 * outlineMask;
    }

    // Up to 10 dynamic point lights with smooth window attenuation (zero hard circle cutoff).
    vec3 pointLight = vec3(0.0);
    vec2 samplePos = sc;
    if (spriteBillboard > 0.5 && surfaceBaseY > 0.5) {
        samplePos.y = mix(sc.y, surfaceBaseY, 0.25);
    }

    for (int i = 0; i < 10; i++) {
        if (float(i) >= numLights) {
            break;
        }
        vec4 lp = lightPosRadius[i];
        vec4 lc = lightColorEnergy[i];
        float radius = max(lp.z, 1.0);
        vec2 delta = lp.xy - samplePos;
        float dist = length(delta);
        if (dist < radius) {
            float u = dist / radius;
            float oneMinusU = 1.0 - u;
            float atten = (oneMinusU * oneMinusU) / (1.0 + 2.2 * u * u);
            float lz = (lp.w > 2.0) ? lp.w : (radius * clamp((lp.w > 0.01) ? lp.w : 0.40, 0.18, 1.25));
            vec3 lightDir3D = safeNormalize(vec3(delta, lz), vec3(0.0, 0.0, 1.0));
            float pNdl = clamp((dot(N, lightDir3D) + 0.45) / 1.45, 0.0, 1.0);
            pointLight += lc.rgb * max(lc.a, 0.0) * atten * pNdl;
        }
    }

    vec3 emissive = (albedo * 0.5 + emissiveColor * 0.5) * max(emissiveBoost, 0.0);
    vec3 lit = albedo * (hemiAmbient + sunColor * energy * ndl * 0.62 + pointLight)
             + sunColor * spec * 0.22
             + rimGlow
             + emissive;

    lit.r = compressShoulder(lit.r);
    lit.g = compressShoulder(lit.g);
    lit.b = compressShoulder(lit.b);

    return vec4(lit, outAlpha);
}
]]

local SUNBEAM_SHADER_CODE = [[
extern number time;
extern number beamAngle;
extern vec3 beamColor;
extern number beamStrength;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 texel = Texel(tex, tc);
    float ca = cos(beamAngle);
    float sa = sin(beamAngle);
    float u = (tc.x - 0.5) * ca - tc.y * sa;

    float w1 = clamp(0.5 + 0.5 * sin(u * 18.0 + time * 0.38), 0.0001, 1.0);
    float w2 = clamp(0.5 + 0.5 * sin(u * 31.0 - time * 0.26 + 1.45), 0.0001, 1.0);
    float w3 = clamp(0.5 + 0.5 * sin(u * 11.0 + time * 0.17 + 2.80), 0.0001, 1.0);

    float shafts = pow(w1, 2.3) * 0.52 + pow(w2, 3.0) * 0.28 + pow(w3, 1.8) * 0.30;
    float shimmer = 0.92 + 0.08 * sin(tc.y * 7.0 - time * 0.50 + u * 4.0);

    float vFade = smoothstep(0.0, 0.10, tc.y) * (1.0 - smoothstep(0.38, 0.88, tc.y));
    float hFade = smoothstep(0.0, 0.16, tc.x) * (1.0 - smoothstep(0.84, 1.0, tc.x));

    float intensity = clamp(shafts * shimmer * vFade * hFade * max(beamStrength, 0.0), 0.0, 1.0);
    intensity *= texel.a * color.a;

    return vec4(beamColor * color.rgb * intensity, intensity);
}
]]

local POST_SHADER_CODE = [[
extern number dofEnabled;
extern number focusY;
extern vec2 texelSize;
extern number bloomStrength;
extern number vignetteStrength;

float luma709(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec4 bloomTap(vec3 s, float tapWeight) {
    float l = luma709(s);
    float mask = smoothstep(0.74, 1.0, l);
    vec3 bright = s * mask;
    float karis = 1.0 / (1.0 + l);
    float w = tapWeight * karis;
    return vec4(bright * w, w);
}

float compressPost(float c) {
    if (c > 0.94) {
        return 0.94 + 0.06 * (1.0 - exp(-(c - 0.94) / 0.24));
    }
    return max(c, 0.0);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 base = Texel(tex, tc);
    vec3 col = base.rgb;

    // Optional subtle vertical depth-of-field blur proportional to distance from focusY.
    if (dofEnabled > 0.5) {
        float coc = smoothstep(0.18, 0.55, abs(tc.y - focusY));
        if (coc > 0.001) {
            vec2 stepUV = texelSize * (1.20 + 1.80 * coc);
            vec2 lo = vec2(0.0);
            vec2 hi = vec2(1.0);
            vec3 blur = col * 0.36;
            blur += Texel(tex, clamp(tc + vec2( stepUV.x, 0.0), lo, hi)).rgb * 0.12;
            blur += Texel(tex, clamp(tc + vec2(-stepUV.x, 0.0), lo, hi)).rgb * 0.12;
            blur += Texel(tex, clamp(tc + vec2(0.0,  stepUV.y), lo, hi)).rgb * 0.12;
            blur += Texel(tex, clamp(tc + vec2(0.0, -stepUV.y), lo, hi)).rgb * 0.12;
            blur += Texel(tex, clamp(tc + vec2( stepUV.x,  stepUV.y) * 0.75, lo, hi)).rgb * 0.04;
            blur += Texel(tex, clamp(tc + vec2(-stepUV.x,  stepUV.y) * 0.75, lo, hi)).rgb * 0.04;
            blur += Texel(tex, clamp(tc + vec2( stepUV.x, -stepUV.y) * 0.75, lo, hi)).rgb * 0.04;
            blur += Texel(tex, clamp(tc + vec2(-stepUV.x, -stepUV.y) * 0.75, lo, hi)).rgb * 0.04;
            col = mix(col, blur, coc * 0.65);
        }
    }

    // Safe Karis-weighted selective bloom (luma > 0.74, 4 diagonal inner + 4 cardinal outer taps).
    if (bloomStrength > 0.001) {
        vec2 d1 = texelSize * 1.8;
        vec2 d2 = texelSize * 3.6;
        vec2 lo = vec2(0.0);
        vec2 hi = vec2(1.0);

        vec4 acc = vec4(0.0);
        acc += bloomTap(Texel(tex, clamp(tc + vec2( d1.x,  d1.y), lo, hi)).rgb, 0.65);
        acc += bloomTap(Texel(tex, clamp(tc + vec2(-d1.x,  d1.y), lo, hi)).rgb, 0.65);
        acc += bloomTap(Texel(tex, clamp(tc + vec2( d1.x, -d1.y), lo, hi)).rgb, 0.65);
        acc += bloomTap(Texel(tex, clamp(tc + vec2(-d1.x, -d1.y), lo, hi)).rgb, 0.65);

        acc += bloomTap(Texel(tex, clamp(tc + vec2( d2.x,  0.0 ), lo, hi)).rgb, 0.35);
        acc += bloomTap(Texel(tex, clamp(tc + vec2(-d2.x,  0.0 ), lo, hi)).rgb, 0.35);
        acc += bloomTap(Texel(tex, clamp(tc + vec2( 0.0,   d2.y), lo, hi)).rgb, 0.35);
        acc += bloomTap(Texel(tex, clamp(tc + vec2( 0.0,  -d2.y), lo, hi)).rgb, 0.35);

        vec3 bloom = acc.rgb / max(acc.a, 0.0001);
        col += bloom * max(bloomStrength, 0.0);
    }

    // Soft highlight shoulder compression above 0.94 so bloom never clips into harsh flat white.
    col.r = compressPost(col.r);
    col.g = compressPost(col.g);
    col.b = compressPost(col.b);

    // Smooth elliptical cinematic vignette centered at (0.5, 0.48).
    vec2 vDelta = (tc - vec2(0.5, 0.48)) * vec2(1.12, 1.22);
    float vDist = length(vDelta);
    float vigFactor = smoothstep(0.42, 0.96, vDist);
    col *= (1.0 - clamp(vignetteStrength, 0.0, 0.95) * vigFactor);

    return vec4(col * color.rgb, base.a * color.a);
}
]]

--------------------------------------------------------------------------------
-- Internal Helpers: Warning Filtering & Uniform Cache
--------------------------------------------------------------------------------

local function isBenignWarningLine(line)
    local lower = line:lower()
    if lower == "" then
        return true
    end
    -- Section headers emitted by LOVE2D / OpenGL drivers even when there are zero warnings.
    if lower:match("^pixel shader:?$")
        or lower:match("^vertex shader:?$")
        or lower:match("^compute shader:?$")
        or lower:match("^shader warnings?:?$")
        or lower:match("^link:?$")
        or lower:match("^program:?$")
    then
        return true
    end
    -- Explicit "no errors / no warnings" status lines from desktop GL drivers.
    if lower:match("^no errors?%.?$")
        or lower:match("^no warnings?%.?$")
        or lower:match("^validation successful%.?$")
        or lower:match("^successfully compiled%.?$")
        or lower:match("^0 errors?,?%s*0 warnings?%.?$")
        or lower:match("^0 warnings?,?%s*0 errors?%.?$")
        or lower:match("^0 error%(s%),?%s*0 warning%(s%)%.?$")
        or lower:match("^0 warning%(s%),?%s*0 error%(s%)%.?$")
    then
        return true
    end
    return false
end

local function extractRealWarnings(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local kept = {}
    for line in (raw .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not isBenignWarningLine(trimmed) then
            kept[#kept + 1] = trimmed
        end
    end
    if #kept == 0 then
        return nil
    end
    return table.concat(kept, "\n")
end

local function compileShader(name, code, warnings)
    if not (love and love.graphics and love.graphics.newShader) then
        warnings[#warnings + 1] = string.format("[%s] love.graphics.newShader unavailable", tostring(name))
        return nil
    end
    local ok, shaderOrErr = pcall(love.graphics.newShader, code)
    if not ok or not shaderOrErr then
        warnings[#warnings + 1] = string.format("[%s] compile error: %s", tostring(name), tostring(shaderOrErr))
        return nil
    end
    local okWarn, warnRaw = pcall(shaderOrErr.getWarnings, shaderOrErr)
    if okWarn and type(warnRaw) == "string" then
        local realWarn = extractRealWarnings(warnRaw)
        if realWarn then
            warnings[#warnings + 1] = string.format("[%s] %s", tostring(name), realWarn)
        end
    end
    return shaderOrErr
end

local function cacheHasUniform(shader, uniform)
    if not shader or type(uniform) ~= "string" or uniform == "" then
        return false
    end
    local perShader = uniformCacheByShader[shader]
    if not perShader then
        perShader = {}
        uniformCacheByShader[shader] = perShader
    end
    local exists = perShader[uniform]
    if exists == nil then
        local ok, res = pcall(shader.hasUniform, shader, uniform)
        exists = (ok and res == true) or false
        perShader[uniform] = exists
    end
    return exists
end

local function initDefaultUniforms(shaderSet)
    if shaderSet.lit then
        Shaders.send(shaderSet, "lit", "hasNormalMap", 0.0)
        Shaders.send(shaderSet, "lit", "normalStrength", 1.0)
        Shaders.send(shaderSet, "lit", "spriteAngle", 0.0)
        Shaders.send(shaderSet, "lit", "spriteBillboard", 1.0)
        Shaders.send(shaderSet, "lit", "surfaceBaseY", 0.0)
        Shaders.send(shaderSet, "lit", "ambientColor", { 0.48, 0.52, 0.58 })
        Shaders.send(shaderSet, "lit", "sunDir", { -0.45, -0.58, 0.68 })
        Shaders.send(shaderSet, "lit", "sunColor", { 1.0, 0.94, 0.80 })
        Shaders.send(shaderSet, "lit", "sunEnergy", 1.25)
        Shaders.send(shaderSet, "lit", "specStrength", 0.18)
        Shaders.send(shaderSet, "lit", "emissiveBoost", 0.0)
        Shaders.send(shaderSet, "lit", "emissiveColor", { 1.0, 1.0, 1.0 })
        Shaders.send(shaderSet, "lit", "screenSize", { 1280.0, 720.0 })
        Shaders.send(shaderSet, "lit", "numLights", 0.0)
    end
    if shaderSet.sunbeam then
        Shaders.send(shaderSet, "sunbeam", "time", 0.0)
        Shaders.send(shaderSet, "sunbeam", "beamAngle", -0.44)
        Shaders.send(shaderSet, "sunbeam", "beamColor", { 1.0, 0.94, 0.78 })
        Shaders.send(shaderSet, "sunbeam", "beamStrength", 0.22)
    end
    if shaderSet.post then
        Shaders.send(shaderSet, "post", "dofEnabled", 0.0)
        Shaders.send(shaderSet, "post", "focusY", 0.62)
        Shaders.send(shaderSet, "post", "texelSize", { 1.0 / 1280.0, 1.0 / 720.0 })
        Shaders.send(shaderSet, "post", "bloomStrength", 0.22)
        Shaders.send(shaderSet, "post", "vignetteStrength", 0.22)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Shaders.load()
    local warnings = {}
    local shaderSet = {
        lit = compileShader("lit", LIT_SHADER_CODE, warnings),
        sunbeam = compileShader("sunbeam", SUNBEAM_SHADER_CODE, warnings),
        post = compileShader("post", POST_SHADER_CODE, warnings),
        _warnings = warnings,
        _uniformCache = {},
    }
    initDefaultUniforms(shaderSet)
    return shaderSet
end

function Shaders.hasUniform(shaderSetOrShader, shaderNameOrUniform, maybeUniform)
    if shaderSetOrShader == nil then
        return false
    end
    if type(shaderSetOrShader) == "table" then
        if type(shaderNameOrUniform) ~= "string" or type(maybeUniform) ~= "string" then
            return false
        end
        local sh = shaderSetOrShader[shaderNameOrUniform]
        if not sh then
            return false
        end
        local setCache = shaderSetOrShader._uniformCache
        if not setCache then
            setCache = {}
            shaderSetOrShader._uniformCache = setCache
        end
        local byName = setCache[shaderNameOrUniform]
        if not byName then
            byName = {}
            setCache[shaderNameOrUniform] = byName
        end
        local exists = byName[maybeUniform]
        if exists == nil then
            exists = cacheHasUniform(sh, maybeUniform)
            byName[maybeUniform] = exists
        end
        return exists
    end
    return cacheHasUniform(shaderSetOrShader, shaderNameOrUniform)
end

function Shaders.safeSend(shader, uniform, ...)
    if not shader or type(uniform) ~= "string" or uniform == "" then
        return false
    end
    if select("#", ...) == 0 or select(1, ...) == nil then
        return false
    end
    if not cacheHasUniform(shader, uniform) then
        return false
    end
    local ok = pcall(shader.send, shader, uniform, ...)
    return ok == true
end

function Shaders.send(shaderSet, shaderName, uniform, ...)
    if shaderSet == nil then
        return false
    end
    if type(shaderSet) ~= "table" then
        return Shaders.safeSend(shaderSet, shaderName, uniform, ...)
    end
    if type(shaderName) ~= "string" or type(uniform) ~= "string" or uniform == "" then
        return false
    end
    if select("#", ...) == 0 or select(1, ...) == nil then
        return false
    end
    local sh = shaderSet[shaderName]
    if not sh then
        return false
    end
    local setCache = shaderSet._uniformCache
    if not setCache then
        setCache = {}
        shaderSet._uniformCache = setCache
    end
    local byName = setCache[shaderName]
    if not byName then
        byName = {}
        setCache[shaderName] = byName
    end
    local exists = byName[uniform]
    if exists == nil then
        exists = cacheHasUniform(sh, uniform)
        byName[uniform] = exists
    end
    if not exists then
        return false
    end
    local ok = pcall(sh.send, sh, uniform, ...)
    return ok == true
end

function Shaders.getWarnings(shaderSet)
    local out = {}
    if type(shaderSet) ~= "table" or type(shaderSet._warnings) ~= "table" then
        return out
    end
    for i = 1, #shaderSet._warnings do
        local w = shaderSet._warnings[i]
        if type(w) == "string" and w ~= "" then
            out[#out + 1] = w
        end
    end
    return out
end

return Shaders
