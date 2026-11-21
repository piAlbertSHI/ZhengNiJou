"""Current inventory/initialization adapter for the existing caloric reference.

No compressible EOS or production-state equivalence is asserted.
"""
import numpy as np

from .caloric_cycle import CaloricCycle
from .transport import advective_faces


def mixed_energy(fluid, temperature, mass, auxiliary_capacity):
    return mass*fluid.enthalpy(temperature)+auxiliary_capacity*(temperature-fluid.reference)


def mixed_temperature(fluid, energy, mass, auxiliary_capacity):
    if mass <= 0 or auxiliary_capacity < 0 or not np.isfinite([energy,mass,auxiliary_capacity]).all():
        raise ValueError('Invalid mixed-body mass/capacity/energy')
    knots=mass*fluid.h_knots+auxiliary_capacity*(fluid.t-fluid.reference)
    if not knots[0] <= energy <= knots[-1]:raise ValueError('Mixed-body energy outside property table')
    i=min(int(np.searchsorted(knots,energy,side='right'))-1,len(fluid.t)-2)
    dh=energy-knots[i];a=mass*fluid.cp[i]+auxiliary_capacity;b=mass*fluid.slopes[i]
    return fluid.t[i]+2*dh/(a+np.sqrt(a*a+2*b*dh))


class CurrentCaloricCycle(CaloricCycle):
    """One resident bed per material, two water chambers, side compensator.

    Qian-style local wall exchange and prescribed rectangular transport are an
    explicit thermal-reference model, not the native Pipe(TL) NTU heat law.
    """
    def __init__(self,contract,fluids):
        if contract.get('current_boundary_schema')!='heatdrive_ecc_current_caloric_boundary_v1':
            raise ValueError('Require the explicit current inventory mapping')
        super().__init__(contract,fluids)
        self.slices['water_chambers']=slice(self.size,self.size+2);self.size+=2
        for name in self.components:
            item=self.components[name]
            self.masses[name]=item['fixed_mass_kg']/item['nodes']
        if (len(contract['buffer_initial_masses_kg'])!=3 or len(contract['water_chambers'])!=2
                or any(c['nodes']!=1 for c in self.components.values() if 'bus_index' in c)
                or contract['water_buffer_role']!='adiabatic_one_port_side_compensator'
                or contract['advection_order'] not in (1,2)):
            raise ValueError('Unregistered boundary, accessory resolution or transport method')

    def initial_state(self):
        y=np.zeros(self.size);s=self.slices;c=self.c;initial=c['initial']
        for name,item in self.components.items():
            y[s[name]]=self.masses[name]*self.fluids[item['fluid']].enthalpy(initial['fluid_T_K'][name])
        for material,key,phase in (('SMA','solid_a','phase_a'),('SE','solid_r','phase_r')):
            y[s[key]]=self.capacities[material]*(np.asarray(initial[key+'_T_K'])-303.15)
            y[s[phase]]=initial[phase]
        y[s['bus_E']]=self.bus_capacity*(np.asarray(initial['bus_T_K'])-303.15)
        for j,material in enumerate(('SMA','SE','SE')):
            y[s['buffer_H']][j]=mixed_energy(self.fluids[material],initial['buffer_T_K'][j],
                c['buffer_initial_masses_kg'][j],c['buffer_auxiliary_capacity_J_K'][j])
        for j,body in enumerate(c['water_chambers']):
            y[s['water_chambers']][j]=body['fixed_mass_kg']*self.fluids['SMA'].enthalpy(body['initial_T_K'])
        return y

    def unpack(self,y,*,check_phase=True):
        if y.shape!=(self.size,) or not np.isfinite(y).all():raise ValueError('Invalid current caloric coordinates')
        s=self.slices;c=self.c;t={};h={}
        for name,item in self.components.items():
            h[name]=y[s[name]]/self.masses[name];t[name]=self.fluids[item['fluid']].temperature(h[name])
        xa,xr=y[s['phase_a']],y[s['phase_r']]
        if check_phase and (min(xa.min(),xr.min()) < -1e-10 or max(xa.max(),xr.max())>1+1e-10):raise ValueError('Phase left its physical interval')
        masses=np.asarray(c['buffer_initial_masses_kg'])+np.r_[0.,y[s['buffer_mass_change']]]
        bt=np.array([mixed_temperature(self.fluids[m],y[s['buffer_H']][j],masses[j],c['buffer_auxiliary_capacity_J_K'][j])
            for j,m in enumerate(('SMA','SE','SE'))])
        bh=np.array([self.fluids[m].enthalpy(bt[j]) for j,m in enumerate(('SMA','SE','SE'))])
        ch=y[s['water_chambers']]/np.array([r['fixed_mass_kg'] for r in c['water_chambers']])
        return dict(T=t,h=h,xa=xa,xr=xr,buffer_mass=masses,buffer_h=bh,buffer_T=bt,
            Ta=303.15+y[s['solid_a']]/self.capacities['SMA'],Tr=303.15+y[s['solid_r']]/self.capacities['SE'],
            bus_T=303.15+y[s['bus_E']]/self.bus_capacity,water_chamber_h=ch,
            water_chamber_T=self.fluids['SMA'].temperature(ch))

    def transport_rhs(self,p,stage,legacy):
        d=np.zeros(self.size);s=self.slices;c=self.c
        ma,mr=c['mass_flow_kg_s']['SMA'],c['mass_flow_kg_s']['SE']
        def advect(name,flow,inlet_h):
            order=2 if legacy else (1 if self.components[name]['nodes']==1 else c['advection_order'])
            faces=advective_faces(p['h'][name],flow,inlet_h,inlet_h,order=order,limiter='MC' if order==2 else 'none')
            d[s[name]]+=faces[:-1]-faces[1:]
            return faces[-1] if flow>0 else -faces[0]
        water_hx='shex' if stage in (1,2) else 'hhex_a'
        direction=ma if stage in (1,2) else -ma
        if legacy:
            out=advect(water_hx,ma,p['buffer_h'][0]);returned=advect('bed_a',direction,out/ma)
            d[s['buffer_H']][0]+=returned-ma*p['buffer_h'][0]
        else:
            # A one-cell chamber is mixed: no extrapolated outlet temperature.
            pressure_h,return_h=p['water_chamber_h']
            d[s['water_chambers']][0]=ma*(return_h-pressure_h)
            out=advect(water_hx,ma,pressure_h);returned=advect('bed_a',direction,out/ma)
            d[s['water_chambers']][1]=returned-ma*return_h
            # The one-port compensator is not a through-flow mixing tank.
        if stage in (2,4):
            donor,receiver,hx,flow=(2,1,'hhex_r',-mr) if stage==2 else (1,2,'chex',mr)
            out=advect('bed_r',flow,p['buffer_h'][donor]);out=advect(hx,mr,out/mr)
            d[s['buffer_H']][donor]-=mr*p['buffer_h'][donor];d[s['buffer_H']][receiver]+=out
            d[s['buffer_mass_change']][donor-1]-=mr;d[s['buffer_mass_change']][receiver-1]+=mr
        return d

    def evaluate(self,y,stage):
        d,p,mechanical=super().evaluate(y,stage)
        d+=self.transport_rhs(p,stage,False)-self.transport_rhs(p,stage,True)
        for name,material,key in (('bed_a','SMA','solid_a'),('bed_r','SE','solid_r')):
            item=self.components[name];k=self.fluids[material].conductivity(p['T'][name]);solid=p['Ta' if material=='SMA' else 'Tr']
            old_UA=(3.66*k*item['surface_m2']/item['Dh_m'] if material=='SMA' or stage in (2,4)
                else np.full(self.n,self.c['se_natural_h_W_m2K']*item['surface_m2']))/self.n
            if material=='SE' and stage in (1,3):new_UA=old_UA
            else:
                pipe_UA=self.c['bed_Nu'][material]*k*item['surface_m2']/item['Dh_m']/self.n
                gate=self.c['active_thermal_gate_G_W_K'][material]
                new_UA=pipe_UA*gate/(pipe_UA+gate)
            change=(new_UA-old_UA)*(solid-p['T'][name]);d[self.slices[name]]+=change;d[self.slices[key]]-=change
        return d,p,mechanical

    def inventory_energy(self,y):
        return super().inventory_energy(y)+y[self.slices['water_chambers']].sum()
