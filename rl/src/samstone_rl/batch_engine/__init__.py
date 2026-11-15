"""Batched in-process backend for high-throughput PPO rollouts.

The scalar :mod:`samstone_rl.fast_engine` remains the rules oracle.  This
package removes bridge serialization and exposes a stable batched API without
changing the observation or action schemas used by existing checkpoints.
"""

from .catalog import NumericStoneCatalog
from .encoding import DirectStateEncoder


def __getattr__(name: str):
    # The numeric catalogue is also consumed by vector_engine. Importing the
    # environment eagerly would make that dependency circular.
    if name == "BatchSamStoneEnv":
        from .env import BatchSamStoneEnv

        return BatchSamStoneEnv
    raise AttributeError(name)


__all__ = ["BatchSamStoneEnv", "DirectStateEncoder", "NumericStoneCatalog"]
