module quat_math;

import std.math;

/** XYZ intrinsic Euler angles in radians → unit quaternion (w, x, y, z). */
void eulerRadToQuat(float ex, float ey, float ez, out float qw, out float qx, out float qy, out float qz)
{
    float cx = cos(ex * 0.5f), sx = sin(ex * 0.5f);
    float cy = cos(ey * 0.5f), sy = sin(ey * 0.5f);
    float cz = cos(ez * 0.5f), sz = sin(ez * 0.5f);
    qw = cx * cy * cz + sx * sy * sz;   
    qx = sx * cy * cz - cx * sy * sz;
    qy = cx * sy * cz + sx * cy * sz;
    qz = cx * cy * sz - sx * sy * cz;
}

/** Unit quaternion (w, x, y, z) → XYZ Euler angles in radians. */
void quatToEulerRad(float qw, float qx, float qy, float qz, out float ex, out float ey, out float ez)
{
    float sinr_cosp = 2.0f * (qw * qx + qy * qz);
    float cosr_cosp = 1.0f - 2.0f * (qx * qx + qy * qy);
    ex = atan2(sinr_cosp, cosr_cosp);
    float sinp = 2.0f * (qw * qy - qz * qx);
    if (fabs(sinp) >= 1.0f)
        ey = copysign(PI / 2.0f, sinp);
    else
        ey = asin(sinp);
    float siny_cosp = 2.0f * (qw * qz + qx * qy);
    float cosy_cosp = 1.0f - 2.0f * (qy * qy + qz * qz);
    ez = atan2(siny_cosp, cosy_cosp);
}
