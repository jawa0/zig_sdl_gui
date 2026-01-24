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
