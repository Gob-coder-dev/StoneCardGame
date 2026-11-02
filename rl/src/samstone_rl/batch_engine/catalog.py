from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.fast_engine import StoneCatalog


@dataclass(frozen=True, slots=True)
class NumericStoneCatalog:
    """Dense, immutable catalogue used by the direct state encoder.

    Stone ids are mapped once at startup.  Card observations can then be
    copied from a contiguous float32 table rather than rebuilt from nested
    dictionaries on every environment transition.
    """

    source: StoneCatalog
    stone_ids: tuple[str, ...]
    id_to_index: dict[str, int]
    card_features: np.ndarray
    affinity_indices: np.ndarray
    effect_flags: np.ndarray

    @classmethod
    def from_catalog(cls, source: StoneCatalog) -> NumericStoneCatalog:
        encoder = ObservationEncoder()
        stone_ids = tuple(source.definitions)
        id_to_index = {stone_id: index for index, stone_id in enumerate(stone_ids)}
        card_features = np.zeros(
            (len(stone_ids), encoder.CARD_FEATURES), dtype=np.float32)
        affinity_indices = np.zeros(len(stone_ids), dtype=np.int8)
        effect_flags = np.zeros(
            (len(stone_ids), len(encoder.EFFECTS)), dtype=np.bool_)
        affinity_map = {name: index for index, name in enumerate(encoder.AFFINITIES)}
        for index, stone_id in enumerate(stone_ids):
            definition = source.definition(stone_id)
            serialized = {
                "stone_id": stone_id,
                "affinity": definition["affinity"],
                "level": int(definition.get("level", 1)),
                "blades": dict(definition.get("blades", {})),
                "long_blades": dict(definition.get("long_blades", {})),
                "shields": dict(definition.get("shields", {})),
                "random_blades": int(definition.get("random_blades", 0)),
                "effects": list(definition.get("effects", [])),
                "coin_flip": str(definition.get("coin_flip", "")),
            }
            card_features[index] = encoder._card(serialized)
            affinity_indices[index] = affinity_map[str(definition["affinity"])]
            effects = definition.get("effects", ())
            effect_flags[index] = [effect in effects for effect in encoder.EFFECTS]
        card_features.setflags(write=False)
        affinity_indices.setflags(write=False)
        effect_flags.setflags(write=False)
        return cls(source, stone_ids, id_to_index, card_features,
                   affinity_indices, effect_flags)

    def index(self, stone_id: str) -> int:
        try:
            return self.id_to_index[stone_id]
        except KeyError as exc:
            raise ValueError(f"pierre inconnue: {stone_id}") from exc
