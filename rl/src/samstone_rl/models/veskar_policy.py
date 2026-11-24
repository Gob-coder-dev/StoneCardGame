"""Model compatibility for archived Veskar experiment checkpoints.

The principal trainer does not enable these extensions. Keeping their inference
contract allows inspection of saved experiment models after removing runners.
"""

from torch import nn
from torch.distributions import Categorical

from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.models.tactical_actor_critic import TacticalActorCritic

OWN_GOD_OFFSET = ObservationEncoder().get_obs_size() - ObservationEncoder.GLOBAL_FEATURES + 11
VESKAR_INDEX = OWN_GOD_OFFSET + ObservationEncoder.GODS.index("veskar")


class VeskarPolicy(TacticalActorCritic):
    def __init__(self, *args, outcome=False, adapter=False, **kwargs):
        super().__init__(*args, **kwargs)
        self.has_outcome = bool(outcome)
        self.has_adapter = bool(adapter)
        if outcome:
            self.outcome_head = nn.Sequential(
                nn.Linear(self.hidden_dim, 64), nn.Tanh(), nn.Linear(64, 3)
            )
        if adapter:
            self.state_adapter = nn.Sequential(
                nn.Linear(self.hidden_dim, 64), nn.Tanh(), nn.Linear(64, self.hidden_dim)
            )
            self.action_adapter = nn.Sequential(
                nn.Linear(self.action_feature_dim, 64), nn.Tanh(), nn.Linear(64, 1)
            )
            self.value_adapter = nn.Linear(self.hidden_dim, 1)
            for module in (self.state_adapter[-1], self.action_adapter[-1], self.value_adapter):
                nn.init.zeros_(module.weight)
                nn.init.zeros_(module.bias)
            for name, parameter in self.named_parameters():
                parameter.requires_grad_(
                    name.startswith(
                        ("state_adapter.", "action_adapter.", "value_adapter.", "outcome_head.")
                    )
                )

    @staticmethod
    def veskar_mask(observations):
        return observations[:, VESKAR_INDEX] > 0.5

    def encode_state(self, observations):
        state = super().encode_state(observations)
        if self.has_adapter:
            state = state + self.veskar_mask(observations).to(state.dtype)[
                :, None
            ] * self.state_adapter(state)
        return state

    def distribution_and_value(self, observations, action_mask, action_features):
        self._validate_inputs(observations, action_mask, action_features)
        state = self.encode_state(observations)
        logits = self.action_logits(state, action_features)
        value = self.critic(state).squeeze(-1)
        if self.has_adapter:
            gate = self.veskar_mask(observations).to(logits.dtype)
            logits = logits + gate[:, None] * self.action_adapter(action_features).squeeze(-1)
            value = value + gate * self.value_adapter(state).squeeze(-1)
        return Categorical(logits=logits.masked_fill(~action_mask, -1e9)), value

    def value(self, observations):
        state = self.encode_state(observations)
        value = self.critic(state).squeeze(-1)
        if self.has_adapter:
            value = value + self.veskar_mask(observations).to(value.dtype) * self.value_adapter(
                state
            ).squeeze(-1)
        return value

    def outcome_logits(self, observations):
        if not self.has_outcome:
            raise ValueError("tete de prediction des issues desactivee")
        return self.outcome_head(self.encode_state(observations))
