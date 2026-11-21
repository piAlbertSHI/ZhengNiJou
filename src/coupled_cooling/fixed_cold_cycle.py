"""Declared CHEX Dirichlet boundary and its signed reaction heat, not a reset."""
import numpy as np
from .current_cycle import CurrentCaloricCycle


class FixedColdCaloricCycle(CurrentCaloricCycle):
    def __init__(self,contract,fluids):
        if contract.get('cold_boundary_mode')!='fixed_reservoir_temperature':raise ValueError('Require the actual fixed-reservoir boundary contract')
        if contract['initial']['bus_T_K'][2]!=contract['cold_reservoir_K']:raise ValueError('Do not reset a warm state to impose a reservoir')
        super().__init__(contract,fluids)
        self.slices['cold_reservoir_heat']=slice(self.size,self.size+1);self.size+=1

    def evaluate(self,y,stage):
        d,p,mechanical=super().evaluate(y,stage)
        # Constant initial energy enforces the given cold temperature. The
        # thermostat supplies the opposing rate, recorded as external heat.
        index=self.slices['bus_E'].start+2
        reaction=-d[index];d[index]=0.;d[self.slices['cold_reservoir_heat']]=reaction
        return d,p,mechanical

    def balance(self,y,initial):
        result=super().balance(y,initial)
        result['net_energy_residual_J']-=float((y[self.slices['cold_reservoir_heat']]-initial[self.slices['cold_reservoir_heat']])[0])
        return result
