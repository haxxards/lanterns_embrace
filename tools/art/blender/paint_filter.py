"""The painted look's finishing pass, done on the rendered picture.

Pure numpy and Pillow (no Blender), so the docs' diagrams use the same code:
see docs/PAINTED_STYLE.md, "Step 5: the finishing pass".

    kuwahara(rgb, alpha)   flat, brush-like patches that keep edges sharp
    finish_painted(img)    kuwahara + a little more colour + a dark outline
"""
import math

import numpy as np
from PIL import Image, ImageFilter


def sector_kernels(radius=5, sectors=8):
    """The Kuwahara filter's soft pie slices: `sectors` weight masks, each
    (2*radius+1) square, summing to 1. Slice k looks in the direction
    -180 + (k + 0.5) * 360/sectors degrees, fading out by angle and distance."""
    r = radius
    y, x = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float64)
    ang = np.arctan2(y, x)
    dist = np.hypot(x, y)
    gauss = np.exp(-(dist ** 2) / (2 * (r / 2.0) ** 2)) * (dist <= r + 0.5)
    kernels = []
    for k in range(sectors):
        mid = -math.pi + (k + 0.5) * 2 * math.pi / sectors
        d = np.angle(np.exp(1j * (ang - mid)))  # angle from the slice's centre line, wrapped to +-pi
        mask = np.exp(-(d ** 2) / (2 * (math.pi / sectors) ** 2)) * gauss
        mask[r, r] = gauss[r, r]  # every slice includes the pixel itself
        kernels.append(mask / mask.sum())
    return kernels


class _Convolver:
    """Convolves same-sized images with one kernel through the FFT (much
    faster than sliding the kernel over every pixel), 'same' size output."""

    def __init__(self, shape, kernel):
        self.shape = shape
        self.full = (shape[0] + kernel.shape[0] - 1, shape[1] + kernel.shape[1] - 1)
        self.off = ((kernel.shape[0] - 1) // 2, (kernel.shape[1] - 1) // 2)
        self.fk = np.fft.rfft2(kernel, self.full)

    def __call__(self, a):
        full = np.fft.irfft2(np.fft.rfft2(a, self.full) * self.fk, self.full)
        return full[self.off[0]:self.off[0] + self.shape[0], self.off[1]:self.off[1] + self.shape[1]]


def kuwahara(rgb, alpha, radius=5, sectors=8, q=6.0):
    """Generalised Kuwahara filter (Papari, Petkov and Campisi, 2007).

    For every pixel, look at `sectors` pie slices of its neighbourhood. In each
    slice work out the average colour and how much the colour varies there
    (the standard deviation). The result is a blend of the slice averages,
    weighted by 1 / variation**q: the calmest slice wins. Near an edge the
    calm slices are the ones lying wholly on one side, so the edge stays crisp
    while flat areas turn into smooth, brush-like patches.

    `rgb` is H x W x 3 and `alpha` H x W, floats from 0 to 1. Every average is
    weighted by alpha so the transparent background doesn't bleed in."""
    w = alpha.astype(np.float64)
    num = np.zeros(rgb.shape, np.float64)
    den = np.zeros(rgb.shape[:2], np.float64)
    for kernel in sector_kernels(radius, sectors):
        conv = _Convolver(w.shape, kernel)
        sw = conv(w) + 1e-6
        mean = np.stack([conv(rgb[..., c] * w) for c in range(3)], -1) / sw[..., None]
        mean_sq = np.stack([conv(rgb[..., c] ** 2 * w) for c in range(3)], -1) / sw[..., None]
        sigma = np.sqrt(np.clip(mean_sq - mean ** 2, 0, None)).sum(-1)  # variance = E[x^2] - E[x]^2
        weight = 1.0 / (1e-4 + sigma) ** q
        num += weight[..., None] * mean
        den += weight
    return np.clip(num / den[..., None], 0, 1)


def finish_painted(img, radius=5, outline_px=3, outline="#1a120c", saturation=1.12, contrast=1.06):
    """Turns a straight-alpha RGBA render into the painted look: Kuwahara
    brushwork, a touch more colour and contrast, and a dark outline."""
    a = np.asarray(img.convert("RGBA")).astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3]
    out = kuwahara(rgb, alpha, radius) if radius > 0 else rgb
    # Saturation: push each colour away from its own grey (luma) value.
    lum = out @ np.array([0.299, 0.587, 0.114])
    out = lum[..., None] + (out - lum[..., None]) * saturation
    # Contrast: push values away from middle grey.
    out = (out - 0.5) * contrast + 0.5
    out = np.clip(out, 0, 1)
    body = Image.fromarray((np.dstack([out, alpha]) * 255).astype(np.uint8), "RGBA")
    if outline_px <= 0:
        return body
    # Outline: grow the silhouette by outline_px in every direction (a max
    # filter), soften it slightly, fill it with the ink colour, put the art on top.
    a_img = Image.fromarray((alpha * 255).astype(np.uint8))
    ring = a_img.filter(ImageFilter.MaxFilter(outline_px * 2 + 1)).filter(ImageFilter.GaussianBlur(outline_px * 0.35))
    col = tuple(int(outline[i:i + 2], 16) for i in (1, 3, 5))
    line = Image.new("RGBA", body.size, (*col, 0))
    line.putalpha(ring.point(lambda v: int(v * 0.92)))
    res = Image.new("RGBA", body.size, (0, 0, 0, 0))
    res.alpha_composite(line)
    res.alpha_composite(body)
    return res
