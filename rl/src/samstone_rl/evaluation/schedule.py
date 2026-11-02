from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class MatchSpec:
    opponent_id: str
    seed: int
    agent_player: int
    first_player: int


def common_schedule(opponent_ids: tuple[str, ...], games_per_side_order: int,
                    seed_base: int) -> tuple[MatchSpec, ...]:
    if games_per_side_order <= 0:
        raise ValueError("games_per_side_order doit être positif")
    schedule: list[MatchSpec] = []
    seed = int(seed_base)
    for opponent_id in opponent_ids:
        for agent_player in (1, 2):
            for first_player in (1, 2):
                for _game in range(games_per_side_order):
                    schedule.append(MatchSpec(opponent_id, seed, agent_player, first_player))
                    seed += 1
    return tuple(schedule)
