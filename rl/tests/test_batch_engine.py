from __future__ import annotations

import numpy as np
import pytest

from samstone_rl.batch_engine import (
    BatchSamStoneEnv,
    DirectStateEncoder,
    NumericStoneCatalog,
)
from samstone_rl.envs.observation import ObservationEncoder
from samstone_rl.envs.samstone_env import DEFAULT_CONFIG, RewardScheme, SamStoneEnv
from samstone_rl.fast_engine import FastSimulator, StoneCatalog
from samstone_rl.opponents import GodotProfileOpponent, RandomOpponent

SCENARIOS = (
    ("veskar", ["devoracle_n3", "griffe_a_jetons_n3", "sou_ricanant_n3", "croupier_manchot_n2",
               "jumeau_de_cuivre_n2", "valet_a_lenvers_n2", "avortons_des_caves_n2", "le_voyeur_n1"]),
    ("nerava", ["porte_fievre_n2", "crache_cendre_n2", "clochelet_malade_n2", "machoire_moisie_n2",
                 "veuve_des_spores_n1", "griffe_septique_n1", "le_nud_hurlant_n1", "devoreur_de_lanternes_n1"]),
    ("kharun", ["eclat_cuirasse_n2", "heaume_errant_n2", "carapace_vide_n2", "osselet_blinde_n2",
                  "chevalier_sans_visage_n1", "golem_de_faience_n1", "avortons_des_caves_n2", "le_sac_a_murmures_n2"]),
    ("ilyr", ["longuepine_n3", "bouche_arbalete_n2", "echassier_des_brumes_n3", "veilleur_bifurque_n2",
                   "lil_empale_n1", "la_croisee_des_regards_n1", "avortons_des_caves_n3", "le_voyeur_n1"]),
    ("sylkha", ["nud_vivant_n3", "bourgeon_mordant_n3", "mante_des_racines_n2", "porte_nid_n2",
                    "fourmilion_des_nerfs_n2", "la_nourrice_nouee_n1", "avortons_des_caves_n2", "devoreur_de_lanternes_n2"]),
    ("enigma", ["collecteur_de_dents_n4", "depeceur_rampant_n4", "recycleur_thoracique_n3", "porte_greffes_n2",
                 "le_demonteur_n2", "la_machine_aux_mille_depouilles_n1", "avortons_des_caves_n3", "le_voyeur_n1"]),
)


def _config(god: str, deck: list[str]) -> dict:
    return {"human_god": god, "ai_god": god,
            "human_deck": deck, "ai_deck": deck}


@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_direct_encoder_matches_public_observation_encoder(god, deck):
    catalog = StoneCatalog()
    simulator = FastSimulator(catalog)
    simulator.reset({**_config(god, deck), "seed": 941, "first_player": 1,
                     "blocked": [[0, 0], [3, 3]]})
    direct = DirectStateEncoder(NumericStoneCatalog.from_catalog(catalog))
    reference = ObservationEncoder()
    turn = 0
    while True:
        state = simulator.state
        assert state is not None
        for observer in (1, 2):
            expected = reference.encode(simulator.serialize_for_player(observer))
            actual = direct.encode(state, observer)
            assert np.array_equal(actual, expected)
        if state.is_game_over:
            break
        legal = simulator.legal_actions()
        simulator.step(legal[(turn * 17) % len(legal)])
        turn += 1


@pytest.mark.parametrize("agent_player", [1, 2])
@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_batch_environment_matches_scalar_environment(god, deck, agent_player):
    config = _config(god, deck)
    reward = RewardScheme(capture=0.0, multi_capture=0.0, terminal=2.0,
                          final_margin=0.1, final_margin_scale=5.0,
                          board_control_delta=0.05, board_control_delta_limit=4)
    scalar = SamStoneEnv(backend="python", opponent=RandomOpponent(),
                         agent_player=agent_player, match_config=config,
                         reward_scheme=reward)
    batch = BatchSamStoneEnv(1, reward)
    options = {"config": {**config, "blocked": [[0, 0]], "first_player": 2}}
    try:
        scalar_observation, scalar_info = scalar.reset(seed=1237, options=options)
        batch_observation, batch_info = batch.reset_one(
            0, seed=1237, opponent=RandomOpponent(), agent_player=agent_player,
            options=options)
        while True:
            assert np.array_equal(batch_observation, scalar_observation)
            assert np.array_equal(batch_info["action_mask"], scalar_info["action_mask"])
            assert batch_info["winner"] == scalar_info["winner"]
            if "episode" in scalar_info:
                assert batch_info["episode"] == scalar_info["episode"]
                break
            action = int(np.flatnonzero(scalar_info["action_mask"])[-1])
            scalar_transition = scalar.step(action)
            batch_transition = batch.step([action])[0]
            scalar_observation, scalar_reward, scalar_done, scalar_truncated, scalar_info = (
                scalar_transition)
            batch_observation, batch_reward, batch_done, batch_truncated, batch_info = (
                batch_transition)
            assert batch_reward == pytest.approx(scalar_reward)
            assert batch_done == scalar_done
            assert batch_truncated == scalar_truncated
            for key in ("capture_reward", "terminal_reward", "final_margin_reward",
                        "control_delta_reward", "agent_captures", "opponent_captures"):
                assert batch_info[key] == pytest.approx(scalar_info[key])
    finally:
        scalar.close()
        batch.close()


def test_batch_environment_rejects_wrong_batch_and_illegal_actions():
    reward = RewardScheme()
    batch = BatchSamStoneEnv(2, reward)
    options = {"config": {**DEFAULT_CONFIG, "first_player": 1, "blocked": []}}
    try:
        batch.reset_many(
            [0, 1], seeds=[1, 2], opponents=[RandomOpponent(), RandomOpponent()],
            agent_players=[1, 1], options=[options, options])
        with pytest.raises(ValueError, match="2 actions attendues"):
            batch.step([0])
        with pytest.raises(ValueError, match="action illegale"):
            batch.step_one(0, 128)
    finally:
        batch.close()


@pytest.mark.parametrize(("precision", "anticipation", "anticipation_probability"), (
    (0.0, False, None), (0.25, False, None),
    (1.0, False, None), (1.0, True, None), (1.0, False, 0.25)))
def test_batch_environment_matches_profile_opponents(
        precision, anticipation, anticipation_probability):
    god, deck = SCENARIOS[4]
    config = _config(god, deck)
    reward = RewardScheme(terminal=2.0, board_control_delta=0.05)
    scalar_opponent = GodotProfileOpponent(
        precision, anticipation, anticipation_probability)
    batch_opponent = GodotProfileOpponent(
        precision, anticipation, anticipation_probability)
    scalar = SamStoneEnv(backend="python", opponent=scalar_opponent,
                         agent_player=1, match_config=config, reward_scheme=reward)
    batch = BatchSamStoneEnv(1, reward)
    options = {"config": {**config, "blocked": [[1, 2]], "first_player": 2}}
    try:
        scalar_observation, scalar_info = scalar.reset(seed=77291, options=options)
        batch_observation, batch_info = batch.reset_one(
            0, seed=77291, opponent=batch_opponent, agent_player=1, options=options)
        while "episode" not in scalar_info:
            assert np.array_equal(batch_observation, scalar_observation)
            assert np.array_equal(batch_info["action_mask"], scalar_info["action_mask"])
            action = int(np.flatnonzero(scalar_info["action_mask"])[0])
            scalar_observation, scalar_reward, scalar_done, _, scalar_info = scalar.step(action)
            batch_observation, batch_reward, batch_done, _, batch_info = batch.step([action])[0]
            assert batch_reward == pytest.approx(scalar_reward)
            assert batch_done == scalar_done
        assert batch_info["episode"] == scalar_info["episode"]
    finally:
        scalar.close()
        batch.close()


@pytest.mark.parametrize(("god", "deck"), SCENARIOS)
def test_vector_tactical_features_match_scalar_oracle_for_complete_games(god, deck):
    config = _config(god, deck)
    reward = RewardScheme(terminal=2.0, board_control_delta=0.05)
    vector = BatchSamStoneEnv(
        1, reward, tactical_features=True, vector_tactical=True)
    oracle = BatchSamStoneEnv(
        1, reward, tactical_features=True, vector_tactical=False)
    options = {"config": {**config, "blocked": [[0, 3]], "first_player": 1}}
    try:
        vector_obs, vector_info = vector.reset_one(
            0, seed=87123, opponent=GodotProfileOpponent(1.0, True),
            agent_player=1, options=options)
        oracle_obs, oracle_info = oracle.reset_one(
            0, seed=87123, opponent=GodotProfileOpponent(1.0, True),
            agent_player=1, options=options)
        while True:
            assert np.array_equal(vector_obs, oracle_obs)
            assert np.array_equal(vector_info["action_mask"], oracle_info["action_mask"])
            assert np.array_equal(
                vector_info["action_features"], oracle_info["action_features"])
            if "episode" in oracle_info:
                assert vector_info["episode"] == oracle_info["episode"]
                break
            action = int(np.flatnonzero(oracle_info["action_mask"])[-1])
            vector_obs, vector_reward, vector_done, _, vector_info = vector.step([action])[0]
            oracle_obs, oracle_reward, oracle_done, _, oracle_info = oracle.step([action])[0]
            assert vector_reward == pytest.approx(oracle_reward)
            assert vector_done == oracle_done
        assert vector.vector_tactical is not None
        metrics = vector.vector_tactical.metrics()
        assert metrics["fallback_actions"] == 0
        assert metrics["coverage"] == 1.0
    finally:
        vector.close()
        oracle.close()


def test_vector_tactical_kernel_reports_real_coverage_on_simple_deck():
    god, deck = SCENARIOS[2]
    batch = BatchSamStoneEnv(
        4, RewardScheme(), tactical_features=True, vector_tactical=True)
    options = [{"config": {**_config(god, deck), "blocked": [], "first_player": 1}}
               for _ in range(4)]
    try:
        batch.reset_many(
            range(4), seeds=range(100, 104),
            opponents=[RandomOpponent() for _ in range(4)],
            agent_players=[1] * 4, options=options)
        assert batch.vector_tactical is not None
        stats = batch.vector_tactical.last_stats
        assert stats.vectorized_states == 4
        assert stats.vectorized_actions > 0
        assert stats.fallback_actions == 0
        assert stats.coverage == 1.0
    finally:
        batch.close()


def test_vector_workspace_is_reused_without_growing_for_same_batch():
    god, deck = SCENARIOS[4]
    batch = BatchSamStoneEnv(
        4, RewardScheme(), tactical_features=True, vector_tactical=True)
    options = [{"config": {**_config(god, deck), "blocked": [], "first_player": 1}}
               for _ in range(4)]
    try:
        batch.reset_many(
            range(4), seeds=range(400, 404),
            opponents=[RandomOpponent() for _ in range(4)],
            agent_players=[1] * 4, options=options)
        assert batch.vector_tactical is not None
        workspace = batch.vector_tactical.workspace
        owners_id = id(workspace.owners)
        allocated = workspace.allocated_bytes
        actions = [int(np.flatnonzero(batch.action_masks[index])[0]) for index in range(4)]
        batch.step(actions)
        assert id(workspace.owners) == owners_id
        assert workspace.allocated_bytes == allocated
        assert workspace.capacity == 4
    finally:
        batch.close()


def test_vector_tactical_batch_matches_scalar_across_all_phase4_scenarios():
    size = len(SCENARIOS)
    reward = RewardScheme(terminal=2.0, board_control_delta=0.05)
    vector = BatchSamStoneEnv(
        size, reward, tactical_features=True, vector_tactical=True)
    oracle = BatchSamStoneEnv(
        size, reward, tactical_features=True, vector_tactical=False)
    seeds = [91000 + index * 97 for index in range(size)]
    options = [
        {"config": {**_config(god, deck),
                    "blocked": [[index % 4, (index * 3) % 4]],
                    "first_player": 1}}
        for index, (god, deck) in enumerate(SCENARIOS)
    ]
    opponents_a = [GodotProfileOpponent(1.0, False, 0.5) for _ in range(size)]
    opponents_b = [GodotProfileOpponent(1.0, False, 0.5) for _ in range(size)]
    try:
        vector_obs, vector_infos = vector.reset_many(
            range(size), seeds=seeds, opponents=opponents_a,
            agent_players=[1] * size, options=options)
        oracle_obs, oracle_infos = oracle.reset_many(
            range(size), seeds=seeds, opponents=opponents_b,
            agent_players=[1] * size, options=options)
        for turn in range(5):
            assert np.array_equal(np.asarray(vector_obs), np.asarray(oracle_obs))
            for vector_info, oracle_info in zip(
                    vector_infos, oracle_infos, strict=True):
                assert np.array_equal(
                    vector_info["action_mask"], oracle_info["action_mask"])
                assert np.array_equal(
                    vector_info["action_features"], oracle_info["action_features"])
            actions = []
            for index, info in enumerate(oracle_infos):
                legal = np.flatnonzero(info["action_mask"])
                actions.append(int(legal[(turn * 11 + index * 7) % len(legal)]))
            vector_transitions = vector.step(actions)
            oracle_transitions = oracle.step(actions)
            vector_obs = [item[0] for item in vector_transitions]
            oracle_obs = [item[0] for item in oracle_transitions]
            vector_infos = [item[4] for item in vector_transitions]
            oracle_infos = [item[4] for item in oracle_transitions]
            for actual, expected in zip(
                    vector_transitions, oracle_transitions, strict=True):
                assert actual[1] == pytest.approx(expected[1])
                assert actual[2] == expected[2]
    finally:
        vector.close()
        oracle.close()
