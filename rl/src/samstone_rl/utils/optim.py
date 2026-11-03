from __future__ import annotations

import math

import torch


class DirectMLAdam(torch.optim.Optimizer):
    """Adam without ``lerp_``, which currently falls back incorrectly on DML.

    State names intentionally match ``torch.optim.Adam`` so CPU checkpoints
    can be resumed on DirectML and conversely.
    """

    def __init__(self, params, lr: float = 1e-3,
                 betas: tuple[float, float] = (0.9, 0.999),
                 eps: float = 1e-8) -> None:
        if lr < 0 or eps < 0 or not 0 <= betas[0] < 1 or not 0 <= betas[1] < 1:
            raise ValueError("parametres Adam invalides")
        super().__init__(params, {"lr": lr, "betas": betas, "eps": eps})

    @torch.no_grad()
    def step(self, closure=None):
        loss = None if closure is None else closure()
        for group in self.param_groups:
            beta1, beta2 = group["betas"]
            for parameter in group["params"]:
                gradient = parameter.grad
                if gradient is None:
                    continue
                if gradient.is_sparse:
                    raise RuntimeError("DirectMLAdam ne prend pas en charge les gradients sparse")
                state = self.state[parameter]
                if not state:
                    state["step"] = 0
                    state["exp_avg"] = torch.zeros_like(parameter)
                    state["exp_avg_sq"] = torch.zeros_like(parameter)
                step = state["step"]
                if isinstance(step, torch.Tensor):
                    step = int(step.detach().cpu().item())
                step += 1
                state["step"] = step
                average = state["exp_avg"]
                square_average = state["exp_avg_sq"]
                average.mul_(beta1).add_(gradient, alpha=1.0 - beta1)
                square_average.mul_(beta2).addcmul_(
                    gradient, gradient, value=1.0 - beta2)
                bias1 = 1.0 - beta1**step
                bias2 = 1.0 - beta2**step
                denominator = square_average.sqrt().div_(math.sqrt(bias2)).add_(group["eps"])
                parameter.addcdiv_(average, denominator, value=-group["lr"] / bias1)
        return loss
