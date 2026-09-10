function contract=Build_HeatDriveECC_PreFeedbackRamp(commands,stop,onset)
% Exact command slope only while feedback is disabled and reset is held.
    if nargin<3,onset=.1;end
    assert(isscalar(onset) && any(onset==[.1 .12]));
    assert(stop==.14,'Only the predeclared pre-feedback ramp diagnostic is allowed.');
    if iscell(commands),commands=[commands{:}];end
    suffixes={'SMAPressureBiasFromWorkspace','SMAFlowTargetFromWorkspace', ...
        'SMAPressureFeedbackEnableFromWorkspace','SMAPressureFeedbackResetFromWorkspace'};
    rows=cell(1,4);
    for k=1:4
        ix=find(endsWith({commands.block},['/' suffixes{k}]));assert(isscalar(ix));c=commands(ix);
        t=c.time_s(:);v=c.values(:);
        assert(numel(t)==numel(v) && t(1)==0 && all(diff(t)>0) && all(isfinite(t)) && all(isfinite(v)));
        assert(t(end)>stop);rows{k}=c;
    end
    bias=rows{1};t=bias.time_s(:);v=bias.values(:);
    assert(strcmp(bias.interpolate,'on') && strcmp(rows{2}.interpolate,'on'));
    boundaries=zeros(1,2);
    for k=3:4
        c=rows{k};expected=k-3;tt=c.time_s(:);vv=c.values(:);
        assert(strcmp(c.interpolate,'off') && vv(1)==expected);
        first=find(vv~=expected,1);assert(~isempty(first));boundaries(k-2)=tt(first);
        assert(stop<tt(first),'Do not cross feedback/reset transition.');
    end
    slopes=diff(v)./diff(t);first=find(slopes~=0,1);assert(~isempty(first));
    assert(abs(t(first)-onset)<1e-15 && t(first)<stop && stop<t(first+1));
    assert(all(v(1:first)==-1e-6) && v(first+1)>-.35 && v(first+1)<.02);
    assert(all(boundaries==t(first+1)) && abs(t(first+1)-.15)<1e-15);
    % Include the right bracketing bias sample without authorizing its event.
    keep=1:first+1;
    contract=struct('schema','heatdrive_ecc_pre_feedback_ramp_v1','stop_time_s',stop, ...
        'time_s',t(keep),'bias_MPa',v(keep),'derivative_MPa_s',[slopes(1:first);0], ...
        'ramp_start_s',t(first),'feedback_event_s',boundaries(1),'reset_release_s',boundaries(2), ...
        'ramp_slope_MPa_s',slopes(first),'integral_held_zero',true,'feedback_disabled',true, ...
        'pressure_min_MPa',-.35,'pressure_max_MPa',.02,'new_filter_added',false, ...
        'full_feedback_derivative_verified',false,'production_recovery_allowed',false);
end
