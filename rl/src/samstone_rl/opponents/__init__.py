"""Politiques adverses utilisées par les environnements."""

from .baselines import GodotProfileOpponent, Opponent, RandomOpponent
from .checkpoint import CheckpointOpponent

__all__ = ["CheckpointOpponent", "GodotProfileOpponent", "Opponent", "RandomOpponent"]
