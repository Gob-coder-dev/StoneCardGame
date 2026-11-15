from .action_space import ActionCodec
from .observation import ObservationEncoder

__all__ = ["ActionCodec", "ObservationEncoder", "RewardScheme", "SamStoneEnv"]


def __getattr__(name: str):
    # Model construction needs the encoders, not a running environment or its
    # opponents. Lazy exports keep that dependency graph acyclic.
    if name in ("RewardScheme", "SamStoneEnv"):
        from .samstone_env import RewardScheme, SamStoneEnv

        return {"RewardScheme": RewardScheme, "SamStoneEnv": SamStoneEnv}[name]
    raise AttributeError(name)
