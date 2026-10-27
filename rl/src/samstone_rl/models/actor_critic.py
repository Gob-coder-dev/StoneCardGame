import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.distributions import Categorical
import numpy as np


class ActorCritic(nn.Module):
    def __init__(self, obs_dim, action_dim, hidden_dim=256):
        super().__init__()
        self.obs_dim = obs_dim
        self.action_dim = action_dim
        
        # Shared backbone
        self.shared = nn.Sequential(
            nn.Linear(obs_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
        )
        
        # Actor head
        self.actor = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Linear(hidden_dim // 2, action_dim)
        )
        
        # Critic head
        self.critic = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Linear(hidden_dim // 2, 1)
        )
    
    def forward(self, x, action_mask=None):
        features = self.shared(x)
        logits = self.actor(features)
        
        if action_mask is not None:
            # Mask illegal actions
            logits = torch.where(action_mask, logits, torch.tensor(-1e8).to(logits.device))
        
        probs = F.softmax(logits, dim=-1)
        dist = Categorical(probs)
        value = self.critic(features)
        
        return dist, value, logits
    
    def get_value(self, x):
        features = self.shared(x)
        return self.critic(features)
    
    def get_action(self, x, action_mask=None, deterministic=False):
        dist, value, logits = self.forward(x, action_mask)
        if deterministic:
            action = torch.argmax(logits, dim=-1)
        else:
            action = dist.sample()
        log_prob = dist.log_prob(action)
        return action, log_prob, value

