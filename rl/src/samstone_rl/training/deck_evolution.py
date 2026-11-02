from __future__ import annotations

import json
from collections.abc import Callable, Iterable
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from samstone_rl.decks import (
    DeckCandidate,
    DeckCatalog,
    DeckGenerator,
    DeckOperators,
    GodotDeckValidator,
    MutationExhausted,
)
from samstone_rl.evaluation import CandidateEvaluation


@dataclass(frozen=True)
class EvolutionConfig:
    population_size: int = 48
    elites: int = 8
    crossover_children: int = 24
    strong_mutations: int = 8
    random_immigrants: int = 8
    tournament_size: int = 4
    generations: int = 20

    def validate(self) -> None:
        total = self.elites + self.crossover_children + self.strong_mutations + self.random_immigrants
        if total != self.population_size:
            raise ValueError(f"la composition de population vaut {total}, attendu {self.population_size}")
        required = (self.population_size, self.elites, self.tournament_size, self.generations)
        optional = (self.crossover_children, self.strong_mutations, self.random_immigrants)
        if any(value <= 0 for value in required) or any(value < 0 for value in optional):
            raise ValueError("paramètres d'évolution non positifs")
        if self.tournament_size > self.population_size:
            raise ValueError("tournament_size depasse la population")


@dataclass(frozen=True)
class RankedCandidate:
    candidate: DeckCandidate
    evaluation: CandidateEvaluation


class EvolutionStateStore:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def save(self, generation: int, god_id: str, population: Iterable[DeckCandidate],
             ranking: Iterable[RankedCandidate], rng: np.random.Generator,
             catalog_checksum: str, policy_checksum: str,
             evolution_config: EvolutionConfig) -> None:
        payload = {
            "version": 2,
            "generation": generation,
            "god_id": god_id,
            "catalog_checksum": catalog_checksum,
            "policy_checksum": policy_checksum,
            "evolution_config": asdict(evolution_config),
            "population": [item.to_dict() for item in population],
            "ranking": [{"candidate": item.candidate.to_dict(),
                         "evaluation": asdict(item.evaluation)} for item in ranking],
            "rng_state": rng.bit_generator.state,
        }
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        temporary.replace(self.path)

    def load(self, catalog: DeckCatalog, expected_policy_checksum: str,
             expected_config: EvolutionConfig) -> tuple[
            int, str, list[DeckCandidate], dict, tuple[RankedCandidate, ...]] | None:
        if not self.path.is_file():
            return None
        payload = json.loads(self.path.read_text(encoding="utf-8"))
        if payload.get("version") != 2:
            raise ValueError("version d'état d'évolution incompatible")
        if payload.get("catalog_checksum") != catalog.checksum:
            raise ValueError("l'état d'évolution utilise un autre catalogue")
        if payload.get("policy_checksum") != expected_policy_checksum:
            raise ValueError("l'état d'évolution utilise une autre politique")
        if payload.get("evolution_config") != asdict(expected_config):
            raise ValueError("l'état d'évolution utilise une autre configuration")
        population = [catalog.candidate(payload["god_id"], item["stone_ids"])
                      for item in payload["population"]]
        ranking = tuple(RankedCandidate(
            catalog.candidate(payload["god_id"], item["candidate"]["stone_ids"]),
            CandidateEvaluation(**item["evaluation"])) for item in payload.get("ranking", []))
        return (int(payload["generation"]), str(payload["god_id"]), population,
                payload["rng_state"], ranking)


class DeckEvolution:
    def __init__(self, catalog: DeckCatalog, validator: GodotDeckValidator,
                 evaluate: Callable[[DeckCandidate], CandidateEvaluation],
                 policy_checksum: str, config: EvolutionConfig,
                 state_store: EvolutionStateStore, seed: int,
                 on_generation: Callable[[int, dict[str, float]], None] | None = None) -> None:
        config.validate()
        self.catalog = catalog
        self.validator = validator
        self.evaluate = evaluate
        self.policy_checksum = policy_checksum
        self.config = config
        self.state_store = state_store
        self.rng = np.random.default_rng(seed)
        self.generator = DeckGenerator(catalog)
        self.operators = DeckOperators(catalog)
        self.on_generation = on_generation

    def run(self, god_id: str, baselines: Iterable[DeckCandidate] = ()) -> tuple[RankedCandidate, ...]:
        restored = self.state_store.load(self.catalog, self.policy_checksum, self.config)
        if restored is None:
            generation = 0
            population = self._initial_population(god_id, baselines)
            last_ranking: tuple[RankedCandidate, ...] = ()
        else:
            generation, restored_god, population, rng_state, last_ranking = restored
            if restored_god != god_id:
                raise ValueError(f"l'état sauvegardé concerne {restored_god}, pas {god_id}")
            self.rng.bit_generator.state = rng_state
        while generation < self.config.generations:
            self.validator.require_all_valid(population)
            ranking = tuple(sorted(
                (RankedCandidate(candidate, self.evaluate(candidate)) for candidate in population),
                key=lambda item: item.evaluation.fitness, reverse=True))
            last_ranking = ranking
            if self.on_generation is not None:
                self.on_generation(generation + 1, self._generation_metrics(ranking))
            generation += 1
            if generation < self.config.generations:
                population = self._breed(ranking)
            self.state_store.save(generation, god_id, population, ranking, self.rng,
                                  self.catalog.checksum, self.policy_checksum, self.config)
        return last_ranking

    def _generation_metrics(self, ranking: tuple[RankedCandidate, ...]) -> dict[str, float]:
        fitness = np.asarray([item.evaluation.fitness for item in ranking], dtype=np.float64)
        best = ranking[0].evaluation
        exact_distances: list[float] = []
        lineage_distances: list[float] = []
        for index, first in enumerate(ranking):
            first_stones = set(first.candidate.stone_ids)
            first_lineages = {self.catalog.variants[item].lineage_id
                              for item in first.candidate.stone_ids}
            for second in ranking[index + 1:]:
                second_stones = set(second.candidate.stone_ids)
                second_lineages = {self.catalog.variants[item].lineage_id
                                   for item in second.candidate.stone_ids}
                exact_distances.append(self._jaccard_distance(first_stones, second_stones))
                lineage_distances.append(self._jaccard_distance(first_lineages, second_lineages))
        return {
            "fitness_best": float(fitness.max()),
            "fitness_mean": float(fitness.mean()),
            "fitness_median": float(np.median(fitness)),
            "fitness_p10": float(np.quantile(fitness, 0.10)),
            "fitness_worst": float(fitness.min()),
            "best_win_rate": best.win_rate,
            "best_wilson_lower": best.wilson_lower,
            "best_worst_matchup_win_rate": best.worst_matchup_win_rate,
            "best_mean_margin": best.mean_margin,
            "unique_decks": float(len({item.candidate.deck_hash for item in ranking})),
            "variant_diversity": float(np.mean(exact_distances)) if exact_distances else 0.0,
            "lineage_diversity": float(np.mean(lineage_distances)) if lineage_distances else 0.0,
        }

    @staticmethod
    def _jaccard_distance(first: set[str], second: set[str]) -> float:
        union = first | second
        return 1.0 - len(first & second) / len(union) if union else 0.0

    def _initial_population(self, god_id: str,
                            baselines: Iterable[DeckCandidate]) -> list[DeckCandidate]:
        population: list[DeckCandidate] = []
        seen: set[str] = set()
        for candidate in baselines:
            self.catalog.require_valid(candidate)
            if candidate.god_id == god_id and candidate.deck_hash not in seen:
                population.append(candidate)
                seen.add(candidate.deck_hash)
        self._fill_random(population, seen, god_id, self.config.population_size)
        return population

    def _breed(self, ranking: tuple[RankedCandidate, ...]) -> list[DeckCandidate]:
        population = [item.candidate for item in ranking[:self.config.elites]]
        seen = {item.deck_hash for item in population}
        target = self.config.elites + self.config.crossover_children
        attempts = 0
        while len(population) < target and attempts < self.config.population_size * 100:
            attempts += 1
            first = self._tournament(ranking)
            second = self._tournament(ranking)
            if first == second:
                continue
            try:
                child = self.operators.crossover(first, second, self.rng)
            except MutationExhausted:
                continue
            if child.deck_hash not in seen:
                population.append(child)
                seen.add(child.deck_hash)
        target += self.config.strong_mutations
        attempts = 0
        while len(population) < target and attempts < self.config.population_size * 100:
            attempts += 1
            try:
                child = self.operators.mutate(self._tournament(ranking), self.rng, mutations=2)
            except MutationExhausted:
                continue
            if child.deck_hash not in seen:
                population.append(child)
                seen.add(child.deck_hash)
        self._fill_random(population, seen, ranking[0].candidate.god_id, self.config.population_size)
        return population

    def _tournament(self, ranking: tuple[RankedCandidate, ...]) -> DeckCandidate:
        count = min(self.config.tournament_size, len(ranking))
        indices = self.rng.choice(len(ranking), size=count, replace=False)
        return max((ranking[int(index)] for index in indices),
                   key=lambda item: item.evaluation.fitness).candidate

    def _fill_random(self, population: list[DeckCandidate], seen: set[str],
                     god_id: str, target: int) -> None:
        attempts = 0
        while len(population) < target and attempts < target * 1000:
            attempts += 1
            candidate = self.generator.random_candidate(god_id, self.rng)
            if candidate.deck_hash not in seen:
                population.append(candidate)
                seen.add(candidate.deck_hash)
        if len(population) != target:
            raise RuntimeError(f"impossible de produire {target} decks uniques")
