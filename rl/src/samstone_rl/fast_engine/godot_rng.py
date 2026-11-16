"""Godot String.hash and PCG32 integer draws for native teacher previews.

Independent implementation of the published PCG32 XSH-RR specification and
Godot's DJB2 string hash / RandomPCG default stream. This is intentionally
separate from the portable LCG used by the network's tactical features.
Reference: godotengine/godot core/math/random_pcg.h and thirdparty/misc/pcg.cpp.
"""

MASK64 = (1 << 64) - 1
MASK32 = (1 << 32) - 1
INCREMENT = (1442695040888963407 << 1) | 1


def string_hash(text: str) -> int:
    value = 5381
    for char in text:
        value = (33 * value + ord(char)) & MASK32
    return value


class GodotRandom:
    def __init__(self, seed: int = 1):
        self.state = 0
        self._draw()
        self.state = (self.state + (seed or 1)) & MASK64
        self._draw()

    def _draw(self) -> int:
        previous = self.state
        self.state = (previous * 6364136223846793005 + INCREMENT) & MASK64
        mixed = (((previous >> 18) ^ previous) >> 27) & MASK32
        rotation = previous >> 59
        return ((mixed >> rotation) | (mixed << ((-rotation) & 31))) & MASK32

    def randrange(self, count: int) -> int:
        if count <= 0:
            raise ValueError("tirage vide")
        if count == 1:
            return 0
        threshold = (1 << 32) % count
        while True:
            value = self._draw()
            if value >= threshold:
                return value % count

    def getstate(self) -> int:
        return self.state

    def setstate(self, state: int) -> None:
        self.state = state
