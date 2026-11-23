"""Check an uploaded logo by what it IS, not by its name or declared type: PNG or JPEG, small, sensible dimensions. No SVG (it can carry scripts)."""

import struct

MAX_BYTES = 512 * 1024
MIN_SIDE, MAX_SIDE = 16, 2048


def sniff(data: bytes) -> tuple[str, int, int] | None:
    """(content type, width, height) for a PNG or a JPEG, else None."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 33 and data[12:16] == b"IHDR":
        w, h = struct.unpack(">II", data[16:24])
        return "image/png", w, h
    if data[:3] == b"\xff\xd8\xff":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                i += 2
                continue
            if marker in (0xFF,):
                i += 1
                continue
            length = struct.unpack(">H", data[i + 2 : i + 4])[0]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack(">HH", data[i + 5 : i + 9])
                return "image/jpeg", w, h
            i += 2 + length
    return None
