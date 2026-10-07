function [node, evidence] = Find_HeatDriveECC_NativeLogNode(log, block)
% Fast hierarchy lookup is accepted only after exact Simulink SID verification.
    started=tic;
    sid=Simulink.ID.getSID(block);
    parts=strsplit(block,'/'); candidate=log; verified=false;
    try
        for k=2:numel(parts)
            assert(ismember(parts{k},candidate.childIds),'Nonliteral log hierarchy.');
            candidate=candidate.child(parts{k});
        end
        leaves=candidate.childIds;
        identified=0;
        for k=1:numel(leaves)
            leaf=candidate.child(leaves{k}); tags=leaf.tags;
            if isempty(tags),continue;end
            assert(iscell(tags) && size(tags,1)==2,'Unexpected native tag layout.');
            index=find(strcmp(tags(1,:),'blockPath'));
            if isempty(index),continue;end
            assert(numel(index)==1 && strcmp(tags{2,index},sid), ...
                'Native leaf has a different Simulink SID.');
            identified=identified+1;
        end
        verified=identified>0;
    catch
        verified=false;
    end
    if verified
        node=candidate; method='literal_hierarchy_exact_leaf_SID';
    else
        node=simscape.logging.findNode(log,block); method='official_recursive_fallback';
    end
    assert(~isempty(node),'Missing actual native log node: %s',block);
    evidence=struct('block_path',block,'SID',sid,'method',method, ...
        'lookup_seconds',toc(started),'exact_SID_verified',verified);
end
