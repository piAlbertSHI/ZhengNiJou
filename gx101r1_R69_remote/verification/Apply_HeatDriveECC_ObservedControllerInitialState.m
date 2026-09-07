function records = Apply_HeatDriveECC_ObservedControllerInitialState(model, mapping, proof_path)
% Explicit measured controller ICs; convert only the two canonical error lags.
    proof=jsondecode(fileread(proof_path));
    assert(proof.equivalence_pass && proof.state_max_difference==0 && proof.output_max_difference==0, ...
        'Require actual canonical state equivalence evidence.');
    records={};
    rows=mapping.named_nonnetwork_state_groups;
    for k=1:numel(rows)
        row=rows(k); block=row.block_path;
        assert(startsWith(block,[model '/']),'Unexpected controller model.');
        kind=get_param(block,'BlockType');
        if any(strcmp(kind,{'UnitDelay','Integrator'}))
            original=get_param(block,'InitialCondition'); initial=slResolve(original,block);
            assert(numel(initial)==numel(row.c200_values),'Initial-condition dimensions changed: %s',block);
            value=reshape(row.c200_values,size(initial));
            set_param(block,'InitialCondition',mat2str(value,17));
            assert(isequal(slResolve(get_param(block,'InitialCondition'),block),value),'Controller IC changed on assignment.');
            records{end+1}=struct('block_path',block,'kind',kind,'original_expression',original, ...
                'new_initial_condition',value,'canonical_replacement',false); %#ok<AGROW>
        elseif strcmp(kind,'TransferFcn')
            assert(any(strcmp(block,{[model '/PressurePI_ErrorLag'],[model '/SMAPressurePI_ErrorLag']})), ...
                'Undeclared transfer-function state.');
            numerator=slResolve(get_param(block,'Numerator'),block);
            denominator=slResolve(get_param(block,'Denominator'),block);
            assert(isequal(numerator,1) && isequal(denominator,[proof.tau_s 1]) && isscalar(row.c200_values), ...
                'Lag basis not covered by the isolated state-equivalence test.');
            [A,B,C,D]=tf2ss(numerator,denominator);
            leaf=get_param(block,'Name'); position=get_param(block,'Position');
            replacements=replace_block(model,'Name',leaf,'simulink/Continuous/State-Space','noprompt');
            assert(isscalar(replacements) && strcmp(replacements{1},block),'Unexpected replacement set.');
            set_param(block,'Position',position,'A',mat2str(A,17),'B',mat2str(B,17), ...
                'C',mat2str(C,17),'D',mat2str(D,17),'InitialCondition',mat2str(row.c200_values,17));
            records{end+1}=struct('block_path',block,'kind',kind,'canonical_replacement',true, ...
                'A',A,'B',B,'C',C,'D',D,'new_initial_condition',row.c200_values); %#ok<AGROW>
        else
            assert(contains(block,'PS') || contains(block,'Simulink-PS'),'Unrecognized non-adapter state: %s',block);
        end
    end
    assert(numel(records)==12 && sum(cellfun(@(r) r.canonical_replacement,records))==2, ...
        'Expected ten explicit ICs and two canonical lag realizations.');
end
