"""Portable preview RNG (schema 2), independent of actual match randomness.

FNV-1a/32 seeds and a 32-bit LCG are also implemented by RLTacticalFeatures.gd.
Changing this algorithm changes the network's input contract.
"""

from __future__ import annotations


class PreviewRandom:
    def __init__(self, seed: int = 1) -> None:
        self.state = int(seed) & 0xFFFFFFFF

    def randrange(self, count: int) -> int:
        if count <= 0:
            raise ValueError("tirage vide")
        if count == 1:
            return 0
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return (self.state >> 16) % count

    def getstate(self) -> int:
        return self.state

    def setstate(self, state: int) -> None:
        self.state = state


def preview_seed(*parts: object) -> int:
    value = 0x811C9DC5
    for byte in ":".join(map(str, parts)).encode("utf-8"):
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value
