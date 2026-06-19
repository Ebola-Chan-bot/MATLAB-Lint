function issues = mlint_mergeIdenticalCaseBranches(filePath)
%mlint_mergeIdenticalCaseBranches 基于 mtree 检测 switch 中相同 case 分支应合并。

if nargin == 0
    issues = "switch 语句中主体相同的连续 case 分支应合并为 case {val1 val2 …}";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

six = FullTree.mtfind('Kind', 'SWITCH').indices;
if isempty(six)
    issues = table(issuesBuilder);
    return;
end

for si = 1:numel(six)
    sw = FullTree.select(six(si));
    swStartPos = lefttreepos(sw);
    swEndPos = righttreepos(sw);

    % 收集该 SWITCH 范围内的 CASE/OTHERWISE 分支
    branches = iCollectBranchesInRange(FullTree, swStartPos, swEndPos);
    if size(branches, 1) < 2
        continue;
    end

    % 扫描连续相同体
    bIdx = 1;
    while bIdx <= size(branches, 1)
        chainStart = bIdx;
        chainKey = branches.body(bIdx);
        bIdx = bIdx + 1;
        while bIdx <= size(branches, 1) && strcmp(branches.body(bIdx), chainKey)
            bIdx = bIdx + 1;
        end
        chainLen = bIdx - chainStart;
        if chainLen >= 2
            vals = strings(1, chainLen);
            for ci = 1:chainLen
                vals(ci) = branches.value(chainStart + ci - 1);
            end
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, double(sw.lineno), "mlint_mergeIdenticalCaseBranches", ...
                sprintf('switch 中 %d 个连续 case 分支内容相同，应合并为 case {%s}', ...
                chainLen, strjoin(vals, " "))}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function branches = iCollectBranchesInRange(FullTree, swStartPos, swEndPos)
allBranches = MATLAB.DataTypes.InsertiveTable();

% 找到范围内所有 CASE 和 OTHERWISE 节点（按节点位置排序）

% 收集 CASE
cix = FullTree.mtfind('Kind', 'CASE').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        cn = FullTree.select(cix(i));
        if lefttreepos(cn) >= swStartPos && righttreepos(cn) <= swEndPos
            allBranches(end+1, {'pos','node','value','isOtherwise'}) = ...
                {lefttreepos(cn), cn.indices, string(strtrim(string(Left(cn).tree2str))), false};
        end
    end
end

% 收集 OTHERWISE
oix = FullTree.mtfind('Kind', 'OTHERWISE').indices;
if ~isempty(oix)
    for i = 1:numel(oix)
        on = FullTree.select(oix(i));
        if lefttreepos(on) >= swStartPos && righttreepos(on) <= swEndPos
            allBranches(end+1, {'pos','node','value','isOtherwise'}) = {lefttreepos(on), on.indices, "otherwise", true};
        end
    end
end

allBranches = table(allBranches);
if isempty(allBranches)
    branches = table('Size', [0 2], 'VariableTypes', {'string','string'}, ...
        'VariableNames', {'value','body'});
    return;
end

% 按节点位置排序
[~, order] = sort(allBranches.pos);
allBranches = allBranches(order, :);

% 为每个分支提取体签名
branchRows = MATLAB.DataTypes.InsertiveTable();
for bi = 1:size(allBranches, 1)
    toPos = swEndPos;
    if bi < size(allBranches, 1)
        toPos = allBranches.pos(bi + 1);
    end
    branchRows(end+1, {'value','body'}) = ...
        {allBranches.value(bi), string(iExtractBodyBetween(FullTree, allBranches.node(bi), toPos, swEndPos))};
end
branches = table(branchRows);
end

% -------------------------------------------------------------------------
function sig = iExtractBodyBetween(FullTree, fromNodeIdx, toPos, swEndPos)
% 提取两个分支节点之间的所有有效语句作为规范化签名。
stmts = MATLAB.Containers.Vector();
fromNode = FullTree.select(fromNodeIdx);

% EQUALS and EXPR nodes are the key statement types to compare
kinds = ["EQUALS", "EXPR", "CALL", "IF", "FOR", "PARFOR", "WHILE", "SWITCH", "TRY", "RETURN"];
for ki = 1:numel(kinds)
    nodes = FullTree.mtfind('Kind', char(kinds(ki)));
    if count(nodes) == 0
        continue;
    end
    nix = nodes.indices;
    for ni = 1:numel(nix)
        nd = FullTree.select(nix(ni));
        if lefttreepos(nd) > lefttreepos(fromNode) && lefttreepos(nd) < toPos ...
                && righttreepos(nd) <= swEndPos
            stmts.PushBack(string(join(split(char(strtrim(lower(string(nd.tree2str))))))));
        end
    end
end

sig = char(strjoin(string(stmts.Data(:)), "||"));
end





