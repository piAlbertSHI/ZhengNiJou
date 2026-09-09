function [dp,p,dlag,dintegral]=Evaluate_HeatDriveECC_SMADerivative(error_normalized,lag,integral,enable,reset,bias,dbias,parameters)
% Classical right derivative between events; no impulse or new filter model.
% parameters = [existing_tau, Kp, Ki, integral_min, integral_max, p_min, p_max].
    assert(numel(parameters)==7 && all(isfinite(parameters)));
    assert(all(isfinite([error_normalized,lag,integral,enable,reset,bias,dbias])));
    assert((enable==0 || enable==1) && (reset==0 || reset==1));
    tau=parameters(1);kp=parameters(2);ki=parameters(3);
    ilo=parameters(4);ihi=parameters(5);plo=parameters(6);phi=parameters(7);
    assert(tau>0 && ilo<ihi && plo<phi);
    dlag=(error_normalized-lag)/tau;
    dintegral=ki*lag;
    if reset~=0 || (integral<=ilo && dintegral<0) || (integral>=ihi && dintegral>0)
        dintegral=0;
    end
    raw=enable*kp*lag+integral+bias;
    dp=enable*kp*dlag+dintegral+dbias;
    p=min(max(raw,plo),phi);
    if raw<plo || raw>phi || (raw==plo && dp<0) || (raw==phi && dp>0)
        dp=0;
    end
end
