function contract=Build_HeatDriveECC_ShiftedInventoryVariants(repo,build,formulation)
% Generate an exact constant-coordinate translation of two protected sources.
    if nargin<3,formulation='aliased';end
    assert(ismember(formulation,{'aliased','intermediates','nonlinear_mass'}));
    assert(isequal(replace_once('aOLDz',"OLD","NEW"),'aNEWz'),'Scalar text replacement regression.');
    assert(~isfolder(build),'Never overwrite a component build.');
    mkdir(build);
    names={'chamber','buffer'};
    folders={'simscape_inventory_specific/+ecc_inventory_specific', ...
        'simscape_buffer_coupled/+ecc_buffer_coupled'};
    hashes={'AFCA0E54FE8A28BB7769DA29E003273A987A43A11B718B66C68C79807BD20539', ...
        '533335CDC7F826B5200C805E462E95B149609E3503BCE64EA42D3AD5431CF5AC'};
    contract=cell(1,2);
    old=pwd;cleanup=onCleanup(@() cd(old));
    for k=1:2
        file=fullfile(repo,'verification',folders{k},['conservative_' names{k} '.ssc']);
        assert(strcmp(file_hash(file),hashes{k}),'Protected physical component changed.');
        original=replace(fileread(file),sprintf('\r\n'),newline);
        candidate=replace_once(original,sprintf('parameters\n'),sprintf(['parameters\n' ...
            '    mass_reference = {0.1, ''kg''}; %% Constant coordinate origin\n' ...
            '    energy_reference = {10000, ''J''}; %% Constant coordinate origin\n']));
        candidate=replace_once(candidate,sprintf('variables\n'),sprintf(['variables\n' ...
            '    mass_delta = {0, ''kg''}; %% Increment from constant origin\n' ...
            '    energy_delta = {0, ''J''}; %% Increment from constant origin\n']));
        candidate=replace_once(candidate,'    der(stored_mass) ==','    der(mass_delta) ==');
        candidate=replace_once(candidate,'    der(stored_energy) ==','    der(energy_delta) ==');
        candidate=replace_once(candidate,sprintf('equations\n'),sprintf(['equations\n' ...
            '    stored_mass == mass_reference + mass_delta;\n' ...
            '    stored_energy == energy_reference + energy_delta;\n']),true);
        package=['ecc_shifted_' names{k}];
        if ~strcmp(formulation,'aliased')
            % Remove absolute aliases from the variable list; keep them observable.
            term_header=sprintf(['intermediates (ExternalAccess = observe)\n' ...
                '    stored_mass = mass_reference + mass_delta;\n' ...
                '    stored_energy = energy_reference + energy_delta;\n']);
            for name={'stored_mass','stored_energy','rho_I','u_I'}
                declaration=regexp(candidate,['(?m)^    ' name{1} ' = [^\r\n]*\n'],'match');
                assert(isscalar(declaration));candidate=replace_once(candidate,declaration{1},'');
            end
            lookup_names={'rho_I','u_I'};lookup_terms=cell(1,2);
            for n=1:2
                equation=regexp(candidate,['(?m)^    ' lookup_names{n} ' == tablelookup[^\r\n]*\n'],'match');
                assert(isscalar(equation));candidate=replace_once(candidate,equation{1},'');
                lookup_terms{n}=strrep(equation{1},' == ',' = ');
            end
            terms=[term_header lookup_terms{:} sprintf('end\n\n')];
            candidate=replace_once(candidate,sprintf('    stored_mass == mass_reference + mass_delta;\n'),'');
            candidate=replace_once(candidate,sprintf('    stored_energy == energy_reference + energy_delta;\n'),'');
            candidate=replace_once(candidate,sprintf('variables (Access = protected)\n'), ...
                [terms sprintf('variables (Access = protected)\n')]);
            if k==2
                % In this fixture the origins equal the original High M/E targets.
                candidate=replace_once(candidate,"mass_delta = {0, 'kg'};", ...
                    "mass_delta = {value = {0, 'kg'}, priority = priority.high};");
                candidate=replace_once(candidate,"energy_delta = {0, 'J'};", ...
                    "energy_delta = {value = {0, 'J'}, priority = priority.high};");
            end
            package=['ecc_increment_' names{k}];
            if strcmp(formulation,'nonlinear_mass')
                candidate=replace_once(candidate,sprintf('parameters\n'), ...
                    sprintf('parameters\n    mass_scale = {0.1, ''kg''}; %% Positive coordinate scale\n'));
                declaration=regexp(candidate,'(?m)^    mass_delta = [^\r\n]*\n','match');assert(isscalar(declaration));
                z="    mass_coordinate = {0, '1'}; % Invertible sinh mass coordinate";
                if k==2,z="    mass_coordinate = {value = {0, '1'}, priority = priority.high}; % Invertible sinh mass coordinate";end
                candidate=replace_once(candidate,declaration{1},[char(z) newline]);
                candidate=replace_once(candidate,'    stored_mass = mass_reference + mass_delta;', ...
                    sprintf(['    mass_delta = mass_scale*sinh(mass_coordinate);\n' ...
                    '    stored_mass = mass_reference + mass_scale*sinh(mass_coordinate);']));
                candidate=replace_once(candidate,'der(mass_delta)', ...
                    'mass_scale*cosh(mass_coordinate)*der(mass_coordinate)');
                candidate=replace_once(candidate,sprintf('equations\n'), ...
                    sprintf('equations\n    assert(mass_scale > 0)\n'),true);
                package=['ecc_nonlinear_' names{k}];
            end
        end
        folder=fullfile(build,['+' package]);mkdir(folder);
        out=fullfile(folder,['conservative_' names{k} '.ssc']);
        fid=fopen(out,'w');assert(fid>=0);fprintf(fid,'%s',candidate);fclose(fid);
        contract{k}=struct('kind',names{k},'package',package,'source',file, ...
            'source_sha256',hashes{k},'generated_source',out,'generated_sha256',file_hash(out), ...
            'physical_equations_changed',false,'coordinate_origin_constant',true,'formulation',formulation);
        cd(build);ssc_build(package);
    end
end

function result=replace_once(text,old,new,first_only)
    if nargin<4,first_only=false;end
    assert(ischar(text) && (isrow(text) || isempty(text)),'Expected one source text buffer.');
    old=char(old);new=char(new);
    locations=strfind(text,old);
    if first_only,assert(~isempty(locations));else,assert(isscalar(locations),'Unexpected source structure.');end
    i=locations(1);result=[text(1:i-1) new text(i+length(old):end)];
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));digest.update(fread(fid,Inf,'*uint8'));
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
