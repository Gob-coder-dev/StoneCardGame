#!/usr/bin/env python3
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'src')))

from samstone_rl.bridge.godot_process import GodotProcess
import random

def main():
    print("Starting sanity check...")
    godot = GodotProcess()
    try:
        godot.start()
        print("Testing ping...")
        if godot.ping():
            print("Ping OK")
        else:
            print("Ping failed")
            return
        
        print("Testing reset...")
        config = {
            "human_deck": ["n01_n1", "n02_n1", "n03_n1", "n04_n1", "n05_n1", "n06_n1", "n07_n1", "n08_n1"],
            "ai_deck": ["n09_n1", "n10_n1", "n11_n1", "n12_n1", "n13_n1", "n14_n1", "n15_n1", "n16_n1"],
            "human_god_id": "veskar",
            "ai_god_id": "nerava",
            "seed": 12345,
            "ai_to_move_first": True
        }
        result = godot.reset(config)
        print(f"Reset OK - legal moves: {len(result.get('legal_moves', []))}")
        
        print("Testing random moves...")
        for i in range(5):
            moves = godot.get_legal_moves()
            if not moves:
                print(f"  Move {i}: No legal moves")
                break
            move = random.choice(moves)
            step_result = godot.step(move)
            print(f"  Move {i}: reward={step_result.get('reward', 0):.3f}, done={step_result.get('done', False)}")
            if step_result.get('done'):
                break
        
        print("Sanity check completed!")
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        godot.close()

if __name__ == "__main__":
    main()

