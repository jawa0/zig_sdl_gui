const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return Vec2{ .x = x, .y = y };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return Vec2{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return Vec2{ .x = self.x * s, .y = self.y * s };
    }

    pub fn rotate(self: Vec2, angle_rad: f32) Vec2 {
        const cos_a = @cos(angle_rad);
        const sin_a = @sin(angle_rad);
        return Vec2{
            .x = self.x * cos_a - self.y * sin_a,
            .y = self.x * sin_a + self.y * cos_a,
        };
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0) return Vec2{ .x = 0, .y = 0 };
        return Vec2{ .x = self.x / len, .y = self.y / len };
    }
};

/// Linear interpolation between two values
/// t = 0 returns a, t = 1 returns b
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Clamp a value between min and max
pub fn clamp(value: f32, min: f32, max: f32) f32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

/// Evaluate a quadratic Bézier curve at parameter t.
/// P0 and P2 are endpoints; control is the single control point.
pub fn bezierQuadratic(p0: Vec2, control: Vec2, p2: Vec2, t: f32) Vec2 {
    const one_t = 1.0 - t;
    return Vec2{
        .x = one_t * one_t * p0.x + 2.0 * one_t * t * control.x + t * t * p2.x,
        .y = one_t * one_t * p0.y + 2.0 * one_t * t * control.y + t * t * p2.y,
    };
}

/// Evaluate the tangent (derivative) of a quadratic Bézier at parameter t.
/// Returns a non-normalized direction vector.
pub fn bezierQuadraticTangent(p0: Vec2, control: Vec2, p2: Vec2, t: f32) Vec2 {
    const one_t = 1.0 - t;
    return Vec2{
        .x = 2.0 * one_t * (control.x - p0.x) + 2.0 * t * (p2.x - control.x),
        .y = 2.0 * one_t * (control.y - p0.y) + 2.0 * t * (p2.y - control.y),
    };
}

/// Derive the Bézier control point C such that the curve passes through
/// `mid` at t=0.5. Given endpoints p0 and p2:
///   C = 2*mid - 0.5*p0 - 0.5*p2
pub fn bezierControlFromMidpoint(p0: Vec2, mid: Vec2, p2: Vec2) Vec2 {
    return Vec2{
        .x = 2.0 * mid.x - 0.5 * p0.x - 0.5 * p2.x,
        .y = 2.0 * mid.y - 0.5 * p0.y - 0.5 * p2.y,
    };
}

/// Compute the axis-aligned bounding box of a quadratic Bézier curve.
pub fn bezierQuadraticAABB(p0: Vec2, control: Vec2, p2: Vec2) struct { min_x: f32, min_y: f32, max_x: f32, max_y: f32 } {
    var min_x = @min(p0.x, p2.x);
    var max_x = @max(p0.x, p2.x);
    var min_y = @min(p0.y, p2.y);
    var max_y = @max(p0.y, p2.y);

    // Check extrema: derivative = 0 gives t = (p0 - control) / (p0 - 2*control + p2)
    const denom_x = p0.x - 2.0 * control.x + p2.x;
    if (@abs(denom_x) > 0.0001) {
        const t_x = (p0.x - control.x) / denom_x;
        if (t_x > 0.0 and t_x < 1.0) {
            const val = bezierQuadratic(p0, control, p2, t_x);
            min_x = @min(min_x, val.x);
            max_x = @max(max_x, val.x);
        }
    }
    const denom_y = p0.y - 2.0 * control.y + p2.y;
    if (@abs(denom_y) > 0.0001) {
        const t_y = (p0.y - control.y) / denom_y;
        if (t_y > 0.0 and t_y < 1.0) {
            const val = bezierQuadratic(p0, control, p2, t_y);
            min_y = @min(min_y, val.y);
            max_y = @max(max_y, val.y);
        }
    }

    return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
}

pub const Transform = struct {
    position: Vec2,
    rotation: f32, // radians
    scale: Vec2,

    pub fn init(position: Vec2, rotation: f32, scale: Vec2) Transform {
        return Transform{
            .position = position,
            .rotation = rotation,
            .scale = scale,
        };
    }

    pub fn identity() Transform {
        return Transform{
            .position = Vec2{ .x = 0, .y = 0 },
            .rotation = 0,
            .scale = Vec2{ .x = 1, .y = 1 },
        };
    }

    pub fn toMatrix(self: Transform) Mat2x3 {
        const cos_r = @cos(self.rotation);
        const sin_r = @sin(self.rotation);

        return Mat2x3{
            .m = [6]f32{
                cos_r * self.scale.x, -sin_r * self.scale.y, self.position.x,
                sin_r * self.scale.x,  cos_r * self.scale.y, self.position.y,
            },
        };
    }

    pub fn transformPoint(self: Transform, point: Vec2) Vec2 {
        // Scale
        var p = Vec2{
            .x = point.x * self.scale.x,
            .y = point.y * self.scale.y,
        };

        // Rotate
        if (self.rotation != 0) {
            p = p.rotate(self.rotation);
        }

        // Translate
        return p.add(self.position);
    }
};

pub const Mat2x3 = struct {
    // Affine transform matrix in column-major order:
    // | m[0] m[2] m[4] |   | sx*cos  -sy*sin  tx |
    // | m[1] m[3] m[5] | = | sx*sin   sy*cos  ty |
    m: [6]f32,

    pub fn identity() Mat2x3 {
        return Mat2x3{
            .m = [6]f32{ 1, 0, 0, 1, 0, 0 },
        };
    }

    pub fn transformPoint(self: Mat2x3, point: Vec2) Vec2 {
        return Vec2{
            .x = self.m[0] * point.x + self.m[2] * point.y + self.m[4],
            .y = self.m[1] * point.x + self.m[3] * point.y + self.m[5],
        };
    }

    pub fn multiply(self: Mat2x3, other: Mat2x3) Mat2x3 {
        return Mat2x3{
            .m = [6]f32{
                self.m[0] * other.m[0] + self.m[2] * other.m[1],
                self.m[1] * other.m[0] + self.m[3] * other.m[1],
                self.m[0] * other.m[2] + self.m[2] * other.m[3],
                self.m[1] * other.m[2] + self.m[3] * other.m[3],
                self.m[0] * other.m[4] + self.m[2] * other.m[5] + self.m[4],
                self.m[1] * other.m[4] + self.m[3] * other.m[5] + self.m[5],
            },
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;

// Vec2 Tests
test "Vec2.init" {
    const v = Vec2.init(3.0, 4.0);
    try expectEqual(3.0, v.x);
    try expectEqual(4.0, v.y);
}

test "Vec2.add" {
    const a = Vec2{ .x = 1.0, .y = 2.0 };
    const b = Vec2{ .x = 3.0, .y = 4.0 };
    const result = a.add(b);
    try expectEqual(4.0, result.x);
    try expectEqual(6.0, result.y);
}

test "Vec2.sub" {
    const a = Vec2{ .x = 5.0, .y = 8.0 };
    const b = Vec2{ .x = 2.0, .y = 3.0 };
    const result = a.sub(b);
    try expectEqual(3.0, result.x);
    try expectEqual(5.0, result.y);
}

test "Vec2.scale" {
    const v = Vec2{ .x = 2.0, .y = 3.0 };
    const result = v.scale(2.5);
    try expectEqual(5.0, result.x);
    try expectEqual(7.5, result.y);
}

test "Vec2.length" {
    const v = Vec2{ .x = 3.0, .y = 4.0 };
    try expectEqual(5.0, v.length());
}

test "Vec2.length zero vector" {
    const v = Vec2{ .x = 0.0, .y = 0.0 };
    try expectEqual(0.0, v.length());
}

test "Vec2.normalize" {
    const v = Vec2{ .x = 3.0, .y = 4.0 };
    const n = v.normalize();
    try expectApproxEqAbs(0.6, n.x, 0.0001);
    try expectApproxEqAbs(0.8, n.y, 0.0001);
    try expectApproxEqAbs(1.0, n.length(), 0.0001);
}

test "Vec2.normalize zero vector" {
    const v = Vec2{ .x = 0.0, .y = 0.0 };
    const n = v.normalize();
    try expectEqual(0.0, n.x);
    try expectEqual(0.0, n.y);
}

test "Vec2.rotate 90 degrees" {
    const v = Vec2{ .x = 1.0, .y = 0.0 };
    const rotated = v.rotate(std.math.pi / 2.0);
    try expectApproxEqAbs(0.0, rotated.x, 0.0001);
    try expectApproxEqAbs(1.0, rotated.y, 0.0001);
}

test "Vec2.rotate 180 degrees" {
    const v = Vec2{ .x = 1.0, .y = 0.0 };
    const rotated = v.rotate(std.math.pi);
    try expectApproxEqAbs(-1.0, rotated.x, 0.0001);
    try expectApproxEqAbs(0.0, rotated.y, 0.0001);
}

test "Vec2.rotate negative angle" {
    const v = Vec2{ .x = 1.0, .y = 0.0 };
    const rotated = v.rotate(-std.math.pi / 2.0);
    try expectApproxEqAbs(0.0, rotated.x, 0.0001);
    try expectApproxEqAbs(-1.0, rotated.y, 0.0001);
}

// Transform Tests
test "Transform.identity" {
    const t = Transform.identity();
    try expectEqual(0.0, t.position.x);
    try expectEqual(0.0, t.position.y);
    try expectEqual(0.0, t.rotation);
    try expectEqual(1.0, t.scale.x);
    try expectEqual(1.0, t.scale.y);
}

test "Transform.identity transforms point unchanged" {
    const t = Transform.identity();
    const point = Vec2{ .x = 5.0, .y = 10.0 };
    const result = t.transformPoint(point);
    try expectEqual(point.x, result.x);
    try expectEqual(point.y, result.y);
}

test "Transform.transformPoint with translation" {
    const t = Transform{
        .position = Vec2{ .x = 10.0, .y = 20.0 },
        .rotation = 0.0,
        .scale = Vec2{ .x = 1.0, .y = 1.0 },
    };
    const point = Vec2{ .x = 5.0, .y = 3.0 };
    const result = t.transformPoint(point);
    try expectEqual(15.0, result.x);
    try expectEqual(23.0, result.y);
}

test "Transform.transformPoint with scale" {
    const t = Transform{
        .position = Vec2{ .x = 0.0, .y = 0.0 },
        .rotation = 0.0,
        .scale = Vec2{ .x = 2.0, .y = 3.0 },
    };
    const point = Vec2{ .x = 4.0, .y = 5.0 };
    const result = t.transformPoint(point);
    try expectEqual(8.0, result.x);
    try expectEqual(15.0, result.y);
}

test "Transform.transformPoint with rotation" {
    const t = Transform{
        .position = Vec2{ .x = 0.0, .y = 0.0 },
        .rotation = std.math.pi / 2.0, // 90 degrees
        .scale = Vec2{ .x = 1.0, .y = 1.0 },
    };
    const point = Vec2{ .x = 1.0, .y = 0.0 };
    const result = t.transformPoint(point);
    try expectApproxEqAbs(0.0, result.x, 0.0001);
    try expectApproxEqAbs(1.0, result.y, 0.0001);
}

test "Transform.transformPoint combined" {
    const t = Transform{
        .position = Vec2{ .x = 10.0, .y = 20.0 },
        .rotation = std.math.pi / 2.0,
        .scale = Vec2{ .x = 2.0, .y = 2.0 },
    };
    const point = Vec2{ .x = 1.0, .y = 0.0 };
    const result = t.transformPoint(point);
    // Scale: (2, 0), Rotate 90deg: (0, 2), Translate: (10, 22)
    try expectApproxEqAbs(10.0, result.x, 0.0001);
    try expectApproxEqAbs(22.0, result.y, 0.0001);
}

test "Transform.toMatrix identity" {
    const t = Transform.identity();
    const m = t.toMatrix();
    try expectEqual(1.0, m.m[0]);
    try expectEqual(0.0, m.m[1]);
    try expectEqual(0.0, m.m[2]);
    try expectEqual(1.0, m.m[3]);
    try expectEqual(0.0, m.m[4]);
    try expectEqual(0.0, m.m[5]);
}

test "Transform.toMatrix matches transformPoint" {
    const t = Transform{
        .position = Vec2{ .x = 5.0, .y = 7.0 },
        .rotation = std.math.pi / 4.0, // 45 degrees
        .scale = Vec2{ .x = 2.0, .y = 3.0 },
    };
    const point = Vec2{ .x = 1.0, .y = 1.0 };

    const direct = t.transformPoint(point);
    const via_matrix = t.toMatrix().transformPoint(point);

    try expectApproxEqAbs(direct.x, via_matrix.x, 0.0001);
    try expectApproxEqAbs(direct.y, via_matrix.y, 0.0001);
}

// Mat2x3 Tests
test "Mat2x3.identity" {
    const m = Mat2x3.identity();
    try expectEqual(1.0, m.m[0]);
    try expectEqual(0.0, m.m[1]);
    try expectEqual(0.0, m.m[2]);
    try expectEqual(1.0, m.m[3]);
    try expectEqual(0.0, m.m[4]);
    try expectEqual(0.0, m.m[5]);
}

test "Mat2x3.identity transforms point unchanged" {
    const m = Mat2x3.identity();
    const point = Vec2{ .x = 3.0, .y = 7.0 };
    const result = m.transformPoint(point);
    try expectEqual(point.x, result.x);
    try expectEqual(point.y, result.y);
}

test "Mat2x3.transformPoint with translation" {
    const m = Mat2x3{
        .m = [6]f32{ 1, 0, 0, 1, 10, 20 },
    };
    const point = Vec2{ .x = 5.0, .y = 3.0 };
    const result = m.transformPoint(point);
    try expectEqual(15.0, result.x);
    try expectEqual(23.0, result.y);
}

test "Mat2x3.transformPoint with scale" {
    const m = Mat2x3{
        .m = [6]f32{ 2, 0, 0, 3, 0, 0 },
    };
    const point = Vec2{ .x = 4.0, .y = 5.0 };
    const result = m.transformPoint(point);
    try expectEqual(8.0, result.x);
    try expectEqual(15.0, result.y);
}

test "Mat2x3.multiply identity" {
    const m1 = Mat2x3.identity();
    const m2 = Mat2x3.identity();
    const result = m1.multiply(m2);

    for (0..6) |i| {
        try expectEqual(Mat2x3.identity().m[i], result.m[i]);
    }
}

test "Mat2x3.multiply translation" {
    const t1 = Mat2x3{
        .m = [6]f32{ 1, 0, 0, 1, 5, 10 },
    };
    const t2 = Mat2x3{
        .m = [6]f32{ 1, 0, 0, 1, 3, 7 },
    };
    const result = t1.multiply(t2);

    // Translation should add: (5+3, 10+7)
    try expectEqual(8.0, result.m[4]);
    try expectEqual(17.0, result.m[5]);
}

test "Mat2x3.multiply scale" {
    const s1 = Mat2x3{
        .m = [6]f32{ 2, 0, 0, 3, 0, 0 },
    };
    const s2 = Mat2x3{
        .m = [6]f32{ 4, 0, 0, 5, 0, 0 },
    };
    const result = s1.multiply(s2);

    // Scale should multiply: (2*4, 3*5)
    try expectEqual(8.0, result.m[0]);
    try expectEqual(15.0, result.m[3]);
}

