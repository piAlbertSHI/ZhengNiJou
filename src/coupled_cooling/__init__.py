"""Reference models for coupled heat-driven elastocaloric cooling."""

from .caloric_cycle import CaloricFluid
from .fixed_cold_cycle import FixedColdCaloricCycle

__all__ = ["CaloricFluid", "FixedColdCaloricCycle"]
