"""
texlib: tileable procedural texture building blocks (numpy), for blender/textures.py.

Every function works on coordinate arrays in tile space: x, y in [0, 1) wrap at 1 (so anything
built from them tiles seamlessly), shaped like the image (rows = y, down the image). Heights are
in metres so normal maps come out at true strength for the tile's real size.

Normal maps are tangent-space, OpenGL convention (green = up the image), which is what Roblox and
Blender both read.
"""

import math
import os

import numpy as np

F = np.float32


def grid(size):
    """x (across) and y (down) coordinates of each pixel's centre, in [0, 1)."""
    c = (np.arange(size, dtype=F) + 0.5) / size
    x, y = np.meshgrid(c, c)
    return x, y


def fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


class Noise:
    """Seeded periodic noise: Perlin, fBm, Worley (cellular), all wrapping at 1."""

    def __init__(self, seed):
        self.rng = np.random.default_rng(seed)

    def perlin(self, x, y, cx, cy=None):
        """Gradient noise with `cx` x `cy` lattice cells per tile, about [-1, 1]."""
        cy = cx if cy is None else cy
        a = self.rng.uniform(0, 2 * math.pi, (cy, cx)).astype(F)
        gx, gy = np.cos(a), np.sin(a)
        X, Y = x * cx, y * cy
        i0, j0 = np.floor(X).astype(np.int64), np.floor(Y).astype(np.int64)
        fx, fy = (X - i0).astype(F), (Y - j0).astype(F)
        i0m, j0m = i0 % cx, j0 % cy
        i1m, j1m = (i0 + 1) % cx, (j0 + 1) % cy

        def dot(i, j, dx, dy):
            return gx[j, i] * dx + gy[j, i] * dy

        n00 = dot(i0m, j0m, fx, fy)
        n10 = dot(i1m, j0m, fx - 1, fy)
        n01 = dot(i0m, j1m, fx, fy - 1)
        n11 = dot(i1m, j1m, fx - 1, fy - 1)
        ux, uy = fade(fx), fade(fy)
        a0 = n00 + ux * (n10 - n00)
        a1 = n01 + ux * (n11 - n01)
        return ((a0 + uy * (a1 - a0)) * 1.41).astype(F)

    def fbm(self, x, y, cells, octaves=5, gain=0.5, lac=2, cy=None):
        """Fractal sum of Perlin octaves, about [-1, 1]."""
        total = np.zeros_like(x)
        amp, norm = 1.0, 0.0
        cx, cyy = cells, (cells if cy is None else cy)
        for _ in range(octaves):
            total += amp * self.perlin(x, y, int(round(cx)), int(round(cyy)))
            norm += amp
            amp *= gain
            cx *= lac
            cyy *= lac
        return (total / norm).astype(F)

    def ridged(self, x, y, cells, octaves=5, gain=0.5):
        """Ridged fBm (sharp crests where the noise crosses zero), [0, 1]."""
        total = np.zeros_like(x)
        amp, norm, c = 1.0, 0.0, cells
        for _ in range(octaves):
            total += amp * (1 - np.abs(self.perlin(x, y, int(c))))
            norm += amp
            amp *= gain
            c *= 2
        return (total / norm).astype(F)

    def worley(self, x, y, cells, jitter=1.0, cy=None):
        """Cellular noise: distance to the nearest and second-nearest feature point (in cell units)
        and the nearest point's cell id (0 .. cx * cy - 1)."""
        cy = cells if cy is None else cy
        cx = cells
        off = self.rng.uniform(0.5 - jitter / 2, 0.5 + jitter / 2, (cy, cx, 2)).astype(F)
        X, Y = x * cx, y * cy
        ci, cj = np.floor(X).astype(np.int64), np.floor(Y).astype(np.int64)
        f1 = np.full(x.shape, np.inf, F)
        f2 = np.full(x.shape, np.inf, F)
        ids = np.zeros(x.shape, np.int64)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                ni, nj = ci + di, cj + dj
                wi, wj = ni % cx, nj % cy
                px = ni + off[wj, wi, 0]
                py = nj + off[wj, wi, 1]
                d = np.hypot(px - X, py - Y).astype(F)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                ids = np.where(closer, wj * cx + wi, ids)
                f1 = np.where(closer, d, f1)
        return f1, f2, ids

    def per_cell(self, count, lo=0.0, hi=1.0):
        return self.rng.uniform(lo, hi, count).astype(F)


def blur(img, sigma_px):
    """Periodic Gaussian blur (FFT), sigma in pixels. Works on (H, W) or (H, W, C)."""
    if sigma_px <= 0:
        return img
    h, w = img.shape[:2]
    fy = np.fft.fftfreq(h).astype(F)[:, None]
    fx = np.fft.fftfreq(w).astype(F)[None, :]
    g = np.exp(-2 * (math.pi * sigma_px) ** 2 * (fx * fx + fy * fy))
    if img.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(img) * g)).astype(F)
    out = np.empty_like(img)
    for c in range(img.shape[2]):
        out[..., c] = np.real(np.fft.ifft2(np.fft.fft2(img[..., c]) * g))
    return out.astype(F)


def normal_map(height_m, tile_m, strength=1.0):
    """Tangent-space normal (OpenGL: +y up the image) from a height field in metres."""
    size = height_m.shape[0]
    px = tile_m / size
    dx = (np.roll(height_m, -1, axis=1) - np.roll(height_m, 1, axis=1)) / (2 * px)
    dy = (np.roll(height_m, -1, axis=0) - np.roll(height_m, 1, axis=0)) / (2 * px)
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx * inv, ny * inv, nz * inv], axis=-1)
    return (n * 0.5 + 0.5).astype(F)


def splat(size, xs, ys, weights, channels=None):
    """Accumulate point samples (pixel coords, wrapped) into an image; `channels` (N, C) adds
    weighted colours alongside. Returns (weight image, colour sum image or None)."""
    xi = np.mod(np.round(xs).astype(np.int64), size)
    yi = np.mod(np.round(ys).astype(np.int64), size)
    flat = yi * size + xi
    w = np.bincount(flat, weights=weights, minlength=size * size).astype(F).reshape(size, size)
    col = None
    if channels is not None:
        col = np.zeros((size, size, channels.shape[1]), F)
        for c in range(channels.shape[1]):
            col[..., c] = np.bincount(flat, weights=weights * channels[:, c], minlength=size * size).reshape(size, size)
    return w, col


def strokes(rng, size, count, length_px, angle=None, angle_spread=math.pi, samples=8, taper=True):
    """Sample points along `count` short straight strokes (blades, needles, fibres): returns xs, ys,
    per-sample weight, and each sample's stroke index."""
    x0 = rng.uniform(0, size, count)
    y0 = rng.uniform(0, size, count)
    L = rng.uniform(length_px[0], length_px[1], count)
    if angle is None:
        a = rng.uniform(0, 2 * math.pi, count)
    else:
        a = angle + rng.uniform(-angle_spread / 2, angle_spread / 2, count)
    t = np.linspace(0, 1, samples)
    xs = (x0[:, None] + np.cos(a)[:, None] * L[:, None] * t[None, :]).ravel()
    ys = (y0[:, None] + np.sin(a)[:, None] * L[:, None] * t[None, :]).ravel()
    w = np.ones((count, samples))
    if taper:
        w = w * (1.0 - 0.7 * t[None, :])
    idx = np.repeat(np.arange(count), samples)
    return xs, ys, w.ravel(), idx


def to_u8(img):
    return np.clip(np.round(np.asarray(img, np.float64) * 255.0), 0, 255).astype(np.uint8)


def save_image(path, img, quality=92):
    """Write an image (H, W), (H, W, 3) or (H, W, 4) in [0, 1] as JPEG (no alpha) or PNG (by the
    path's extension), through Blender's image API."""
    import bpy

    arr = np.asarray(img, F)
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)
    h, w, c = arr.shape
    if c == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1), F)], axis=-1)
    alpha = c == 4
    name = os.path.basename(path)
    image = bpy.data.images.new(name, w, h, alpha=alpha)
    # Blender's rows run bottom to top
    image.pixels.foreach_set(np.clip(arr[::-1], 0, 1).astype(F).ravel())
    image.filepath_raw = path
    image.file_format = "PNG" if path.lower().endswith(".png") else "JPEG"
    if image.file_format == "PNG":
        image.save()
    else:
        image.save(quality=quality)
    bpy.data.images.remove(image)
