import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
import yaml
from pathlib import Path
from torch.utils.tensorboard import SummaryWriter
from samstone_rl.envs.samstone_env import SamStoneEnv
from samstone_rl.models.actor_critic import ActorCritic
from samstone_rl.utils.seeding import set_seed


class PPOTrainer:
    def __init__(self, config_path):
        with open(config_path) as f:
            self.config = yaml.safe_load(f)
        
        set_seed(self.config['seed'])
        self.device = torch.device("cpu")  # Use CPU for stability first
        
        self.env = SamStoneEnv()
        obs, _ = self.env.reset(seed=self.config['seed'])
        self.obs_dim = obs.shape[0]
        self.action_dim = self.env.action_space.n
        
        self.agent = ActorCritic(self.obs_dim, self.action_dim, self.config['hidden_dim']).to(self.device)
        self.optimizer = optim.Adam(self.agent.parameters(), lr=self.config['learning_rate'], eps=1e-5)
        
        self.writer = SummaryWriter(f"runs/ppo_{self.config['seed']}")
    
    def train(self):
        num_steps = self.config['num_steps']
        total_timesteps = self.config['total_timesteps']
        num_updates = total_timesteps // num_steps
        
        obs = torch.zeros((num_steps, self.obs_dim)).to(self.device)
        actions = torch.zeros(num_steps).to(self.device)
        logprobs = torch.zeros(num_steps).to(self.device)
        rewards = torch.zeros(num_steps).to(self.device)
        dones = torch.zeros(num_steps).to(self.device)
        values = torch.zeros(num_steps).to(self.device)
        masks = torch.zeros((num_steps, self.action_dim), dtype=torch.bool).to(self.device)
        
        next_obs, info = self.env.reset(seed=self.config['seed'])
        next_obs = torch.Tensor(next_obs).to(self.device)
        next_done = torch.zeros(1).to(self.device)
        
        global_step = 0
        for update in range(1, num_updates + 1):
            for step in range(num_steps):
                global_step += 1
                obs[step] = next_obs
                dones[step] = next_done
                
                mask = torch.Tensor(info['legal_action_mask']).to(self.device)
                masks[step] = mask
                
                with torch.no_grad():
                    action, logprob, value = self.agent.get_action(next_obs.unsqueeze(0), mask.unsqueeze(0))
                    values[step] = value.flatten()
                actions[step] = action
                logprobs[step] = logprob
                
                next_obs_np, reward, terminated, truncated, info = self.env.step(action.cpu().numpy()[0])
                done = terminated or truncated
                rewards[step] = reward
                next_obs = torch.Tensor(next_obs_np).to(self.device)
                next_done = torch.Tensor([done]).to(self.device)
                
                if done:
                    next_obs, info = self.env.reset()
                    next_obs = torch.Tensor(next_obs).to(self.device)
            
            # Compute advantages
            with torch.no_grad():
                next_value = self.agent.get_value(next_obs.unsqueeze(0)).reshape(1, -1)
                advantages = torch.zeros_like(rewards).to(self.device)
                lastgaelam = 0
                for t in reversed(range(num_steps)):
                    if t == num_steps - 1:
                        nextnonterminal = 1.0 - next_done
                        nextvalues = next_value
                    else:
                        nextnonterminal = 1.0 - dones[t + 1]
                        nextvalues = values[t + 1]
                    delta = rewards[t] + self.config['gamma'] * nextvalues * nextnonterminal - values[t]
                    advantages[t] = lastgaelam = delta + self.config['gamma'] * self.config['gae_lambda'] * nextnonterminal * lastgaelam
                returns = advantages + values
            
            # Flatten
            b_obs = obs.reshape((-1, self.obs_dim))
            b_logprobs = logprobs.reshape(-1)
            b_actions = actions.reshape(-1)
            b_advantages = advantages.reshape(-1)
            b_returns = returns.reshape(-1)
            b_values = values.reshape(-1)
            b_masks = masks.reshape((-1, self.action_dim))
            
            b_inds = np.arange(num_steps)
            for epoch in range(self.config['update_epochs']):
                np.random.shuffle(b_inds)
                for start in range(0, num_steps, num_steps // self.config['num_minibatches']):
                    end = start + num_steps // self.config['num_minibatches']
                    mb_inds = b_inds[start:end]
                    
                    _, newvalue, _ = self.agent(b_obs[mb_inds], b_masks[mb_inds])
                    newvalue = newvalue.view(-1)
                    logratio = b_logprobs[mb_inds] - logprobs[mb_inds]
                    ratio = logratio.exp()
                    
                    mb_advantages = b_advantages[mb_inds]
                    mb_advantages = (mb_advantages - mb_advantages.mean()) / (mb_advantages.std() + 1e-8)
                    
                    pg_loss1 = -mb_advantages * ratio
                    pg_loss2 = -mb_advantages * torch.clamp(ratio, 1 - self.config['clip_coef'], 1 + self.config['clip_coef'])
                    pg_loss = torch.max(pg_loss1, pg_loss2).mean()
                    
                    v_loss = 0.5 * ((newvalue - b_returns[mb_inds]) ** 2).mean()
                    entropy_loss = 0
                    
                    loss = pg_loss - self.config['ent_coef'] * entropy_loss + v_loss * self.config['vf_coef']
                    
                    self.optimizer.zero_grad()
                    loss.backward()
                    nn.utils.clip_grad_norm_(self.agent.parameters(), self.config['max_grad_norm'])
                    self.optimizer.step()
            
            if update % 10 == 0:
                print(f"Update {update}/{num_updates}, Global step {global_step}")
                self.writer.add_scalar("losses/policy_loss", pg_loss.item(), global_step)
                self.writer.add_scalar("losses/value_loss", v_loss.item(), global_step)
        
        self.env.close()
        self.writer.close()
        print("Training completed!")


if __name__ == "__main__":
    config_path = Path(__file__).resolve().parents[3] / "configs" / "ppo_vs_random.yaml"
    trainer = PPOTrainer(config_path)
    trainer.train()

