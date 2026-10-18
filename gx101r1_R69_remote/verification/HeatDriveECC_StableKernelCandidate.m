function y=HeatDriveECC_StableKernelCandidate(u,options)
% Isolated fixed-contract kernel. No model, persisted state, or backend selection.
    N=options.node_count;dt=options.constitutive.simulink_sample_time_s;
    c=options.constitutive;g=options.geometry;a=options.material.SMA;r=options.material.SE;
    assert(N==21 && numel(u)==253 && dt==.001 && c.diagnostic_substeps==32 && ...
        strcmp(c.integration_scheme,'bogacki_shampine_ode3') && c.phase_front_smoothing_1_per_s==0);
    assert(a.T_As_K>a.T_Ms_K && r.T_As_K>r.T_Ms_K);
    assert(options.schedule.tau_cycle_s==10 && numel(options.schedule.stage_end_s)==4);
    u=u(:);t=max(u(1),0);Ta=u(2:22);Tr=u(23:43);xA=u(44:64);xR=u(65:85);
    assert(all(isfinite(u)) && all([xA;xR]>=0 & [xA;xR]<=1));
    stage=find(mod(t,options.schedule.tau_cycle_s)<options.schedule.stage_end_s(:).',1,'first');
    if isempty(stage),stage=4;end
    HeatDriveECC_ConstitutiveStabilityBound(options,stage,dt);
    ratio=g.S_r_m2/g.S_a_m2;
    denominator=g.L_a_m.*ratio./a.E_m_Pa+g.L_r_m./r.E_m_Pa;
    massA=a.rho_kg_per_m3*g.S_a_m2*(g.L_a_m/N);
    massR=r.rho_kg_per_m3*g.S_r_m2*(g.L_r_m/N);
    [sigmaA,sigmaR]=stress(xA,xR,g,a,r,ratio,denominator);
    epsA=a.epsilon_T.*(1.0-xA)-sigmaA./a.E_m_Pa;
    epsR=r.epsilon_T.*xR+sigmaR./r.E_m_Pa;
    energy=zeros(N,4);h=dt/32;
    for sub=1:32
        oldA=xA;oldR=xR;oldEpsA=epsA;oldEpsR=epsR;
        [~,~,k1A,k1R]=rates(xA,xR,Ta,Tr,sigmaA,sigmaR,a,r,c,stage);
        trialA=clamp(xA+0.5.*h.*k1A);trialR=clamp(xR+0.5.*h.*k1R);
        [sA,sR]=stress(trialA,trialR,g,a,r,ratio,denominator);
        [~,~,k2A,k2R]=rates(trialA,trialR,Ta,Tr,sA,sR,a,r,c,stage);
        trialA=clamp(xA+0.75.*h.*k2A);trialR=clamp(xR+0.75.*h.*k2R);
        [sA,sR]=stress(trialA,trialR,g,a,r,ratio,denominator);
        [~,~,k3A,k3R]=rates(trialA,trialR,Ta,Tr,sA,sR,a,r,c,stage);
        xA=clamp(xA+h.*((2.0/9.0).*k1A+(1.0/3.0).*k2A+(4.0/9.0).*k3A));
        xR=clamp(xR+h.*((2.0/9.0).*k1R+(1.0/3.0).*k2R+(4.0/9.0).*k3R));
        [sigmaA,sigmaR]=stress(xA,xR,g,a,r,ratio,denominator);
        epsA=a.epsilon_T.*(1.0-xA)-sigmaA./a.E_m_Pa;
        epsR=r.epsilon_T.*xR+sigmaR./r.E_m_Pa;
        [paiA,paiR,rateA,rateR]=rates(xA,xR,Ta,Tr,sigmaA,sigmaR,a,r,c,stage);
        dxA=xA-oldA;dxR=xR-oldR;
        latentA=-massA.*a.Delta_h_J_per_kg.*dxA;
        latentR=-massR.*r.Delta_h_J_per_kg.*dxR;
        mechA=sigmaA.*(epsA-oldEpsA).*g.S_a_m2.*(g.L_a_m/N);
        stressR=sigmaR.*(epsR-oldEpsR).*g.S_r_m2.*(g.L_r_m/N);
        phaseR=zeros(N,1);loading=dxR>0;unloading=dxR<0;
        phaseR(loading)=-massR.*c.se_loading_work_J_per_kg.*dxR(loading);
        phaseR(unloading)=-massR.*c.se_unloading_work_J_per_kg.*dxR(unloading);
        energy(:,1)=energy(:,1)+latentA;energy(:,2)=energy(:,2)+latentR;
        energy(:,3)=energy(:,3)+mechA;energy(:,4)=energy(:,4)+(stressR+phaseR);
    end
    qA=-(energy(:,1)/dt)-(energy(:,3)/dt);
    qR=-(energy(:,2)/dt)+(energy(:,4)/dt);
    y=[qA;qR;xA;xR;sigmaA.*ones(N,1);sigmaR.*ones(N,1);epsA;epsR;paiA;paiR;rateA;rateR];
end
function [sA,sR]=stress(xA,xR,g,a,r,ratio,denominator)
    numerator=g.L_a_m.*mean(a.epsilon_T.*(1.0-xA),1)-g.L_r_m.*mean(r.epsilon_T.*xR,1);
    sR=numerator./max(denominator,eps);sA=ratio.*sR;
end
function [pA,pR,vA,vR]=rates(xA,xR,Ta,Tr,sA,sR,a,r,c,stage)
    surfaceA=a.T_As_K+(a.T_Ms_K-a.T_As_K).*clamp(xA);
    surfaceR=r.T_As_K+(r.T_Ms_K-r.T_As_K).*clamp(xR);
    if stage==1 || stage==2
        pA=a.C_A_Pa_per_K.*(Ta-surfaceA)-sA;
        pR=sR-r.C_M_Pa_per_K.*(Tr-surfaceR);
        gateA=1.0-exp(-max(pA,0.0)./max(c.drive_width_a_Pa,1.0));
        gateR=1.0-exp(-max(pR,0.0)./max(c.drive_width_r_Pa,1.0));
        vA=-c.rate_a_to_A_1_per_s.*gateA.*xA;
        vR=c.rate_r_load_1_per_s.*gateR.*(1.0-xR);
    else
        pA=sA-a.C_M_Pa_per_K.*(Ta-surfaceA);
        pR=r.C_A_Pa_per_K.*(Tr-surfaceR)-sR;
        gateA=1.0-exp(-max(pA,0.0)./max(c.drive_width_a_Pa,1.0));
        gateR=1.0-exp(-max(pR,0.0)./max(c.drive_width_r_Pa,1.0));
        vA=c.rate_a_to_M_1_per_s.*gateA.*(1.0-xA);
        vR=-c.rate_r_stage3_unload_1_per_s.*gateR.*xR;
    end
    vA=min(max(vA,-c.max_rate_1_per_s),c.max_rate_1_per_s);
    vR=min(max(vR,-c.max_rate_1_per_s),c.max_rate_1_per_s);
end
function y=clamp(x)
    y=min(max(x,0.0),1.0);
end
