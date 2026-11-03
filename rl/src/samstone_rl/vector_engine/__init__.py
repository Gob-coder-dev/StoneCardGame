"""Dense kernels used to accelerate batched SamStone rollouts.

The scalar fast engine remains the rules oracle.  Vector kernels only handle
states for which they can reproduce the oracle exactly and explicitly fall
back for the remaining effect combinations.
"""

from .tactical import VectorTacticalEvaluator, VectorTacticalStats

__all__ = ["VectorTacticalEvaluator", "VectorTacticalStats"]
