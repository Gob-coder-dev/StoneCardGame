"""Archived experiment policies stay readable without experimental runners."""

import pytest
import torch

from samstone_rl.models.policy import build_policy, policy_spec, restore_policy
from samstone_rl.models.veskar_policy import VESKAR_INDEX
from samstone_rl.utils.checkpoints import save_checkpoint


def model_config(**extensions):
    return dict(
        model=dict(
            architecture="tactical_actor_critic",
            hidden_dim=32,
            action_hidden_dim=16,
            veskar_extensions=extensions,
        )
    )


def inputs():
    torch.manual_seed(37)
    obs = torch.randn(3, 929)
    obs[:, VESKAR_INDEX] = torch.tensor([1, 0, 0])
    masks = torch.ones(3, 128, dtype=torch.bool)
    masks[:, 8:] = False
    return obs, masks, torch.randn(3, 128, 79)


@pytest.mark.parametrize("outcome,adapter", [(False, True), (True, False), (True, True)])
def test_extensions_preserve_initial_policy_and_restore_exactly(outcome, adapter):
    base = build_policy(model_config())
    config = model_config(outcome=outcome, adapter=adapter)
    model = build_policy(config)
    model.import_legacy_state(base.state_dict())
    data = inputs()
    expected, expected_value = base.distribution_and_value(*data)
    actual, value = model.distribution_and_value(*data)
    assert torch.equal(expected.logits, actual.logits)
    assert torch.equal(expected_value, value)
    assert torch.equal(value, model.value(data[0]))
    payload = dict(config=config, model=model.state_dict(), policy_spec=policy_spec(config))
    restored = restore_policy(payload)
    assert torch.equal(restored.distribution_and_value(*data)[0].logits, actual.logits)


def test_adapter_training_changes_veskar_only_and_freezes_shared_parameters():
    model = build_policy(model_config(adapter=True))
    data = inputs()
    before = {key: value.clone() for key, value in model.state_dict().items()}
    old, old_value = model.distribution_and_value(*data)
    opt = torch.optim.Adam(model.parameters(), lr=0.01)
    loss = -old.logits[0, 2] + old_value[0].square() + old_value[0]
    loss.backward()
    opt.step()
    new, new_value = model.distribution_and_value(*data)
    assert not torch.equal(old.logits[0], new.logits[0])
    assert torch.equal(old.logits[1:], new.logits[1:])
    assert torch.equal(old_value[1:], new_value[1:])
    assert torch.equal(new_value, model.value(data[0]))
    for key, value in model.state_dict().items():
        if not key.startswith(("state_adapter.", "action_adapter.", "value_adapter.")):
            assert torch.equal(before[key], value)


def test_outcome_supervision_backpropagates_through_shared_backbone():
    model = build_policy(model_config(outcome=True))
    logits = model.outcome_logits(inputs()[0][:1])
    loss = -torch.log_softmax(logits, -1)[0, 0]
    loss.backward()
    assert model.backbone[0].weight.grad.abs().sum() > 0
    assert model.outcome_head[-1].weight.grad.abs().sum() > 0


def test_experimental_extensions_cannot_be_silently_exported_to_godot(tmp_path):
    from samstone_rl.models.export import export_policy

    config = model_config(adapter=True)
    path = tmp_path / "experimental.pt"
    save_checkpoint(path, dict(config=config, model=build_policy(config).state_dict()))
    with pytest.raises(ValueError, match="export Godot non pris en charge"):
        export_policy(path, tmp_path / "policy.bin", allow_unvalidated=True)
