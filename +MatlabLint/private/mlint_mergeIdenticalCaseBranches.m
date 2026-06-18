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
    swStartLn = double(sw.lineno);
    [swEndLn, ~] = pos2lc(sw, righttreepos(sw));

    % 收集该 SWITCH 范围内的 CASE/OTHERWISE 分支
    branches = iCollectBranchesInRange(FullTree, swStartLn, swEndLn);
    if numel(branches) < 2
        continue;
    end

    % 扫描连续相同体
    bIdx = 1;
    while bIdx <= numel(branches)
        chainStart = bIdx;
        chainKey = branches(bIdx).body;
        bIdx = bIdx + 1;
        while bIdx <= numel(branches) && strcmp(branches(bIdx).body, chainKey)
            bIdx = bIdx + 1;
        end
        chainLen = bIdx - chainStart;
        if chainLen >= 2
            vals = strings(1, chainLen);
            for ci = 1:chainLen
                vals(ci) = branches(chainStart + ci - 1).value;
            end
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, swStartLn, "mlint_mergeIdenticalCaseBranches", ...
                sprintf('switch 中 %d 个连续 case 分支内容相同，应合并为 case {%s}', ...
                chainLen, strjoin(vals, " "))}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function branches = iCollectBranchesInRange(FullTree, swStart, swEnd)
allBranches = MATLAB.DataTypes.ArrayBuilder();

% 找到范围内所有 CASE 和 OTHERWISE 节点（按行号排序）

% 收集 CASE
cix = FullTree.mtfind('Kind', 'CASE').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        cn = FullTree.select(cix(i));
        cln = double(cn.lineno);
        if cln >= swStart && cln <= swEnd
            allBranches.Append(struct('line', cln, 'value', ...
                char(strtrim(string(Left(cn).tree2str))), 'isOtherwise', false));
        end
    end
end

% 收集 OTHERWISE
oix = FullTree.mtfind('Kind', 'OTHERWISE').indices;
if ~isempty(oix)
    for i = 1:numel(oix)
        oln = double(FullTree.select(oix(i)).lineno);
        if oln >= swStart && oln <= swEnd
            allBranches.Append(struct('line', oln, 'value', "otherwise", 'isOtherwise', true));
        end
    end
end

allBranches = allBranches.Harvest();
if isempty(allBranches)
    branches = struct('value', {}, 'body', {});
    return;
end

% 按行号排序
[~, order] = sort([allBranches.line]);
allBranches = allBranches(order);

% 为每个分支提取体签名
branches = MATLAB.DataTypes.ArrayBuilder();
for bi = 1:numel(allBranches)
    toLine = swEnd;
    if bi < numel(allBranches)
        toLine = allBranches(bi + 1).line;
    end
    branches.Append(struct('value', allBranches(bi).value, ...
        'body', iExtractBodyBetween(FullTree, allBranches(bi).line, toLine)));
end
branches = branches.Harvest();
end

% -------------------------------------------------------------------------
function sig = iExtractBodyBetween(FullTree, fromLine, toLine)
% 提取两行之间的所有有效语句作为规范化签名。
stmts = strings(0, 1);

% EQUALS and EXPR nodes are the key statement types to compare
kinds = ["EQUALS", "EXPR", "CALL", "IF", "FOR", "PARFOR", "WHILE", "SWITCH", "TRY", "RETURN"];
for ki = 1:numel(kinds)
    nodes = FullTree.mtfind('Kind', kinds(ki));
    if count(nodes) == 0
        continue;
    end
    nix = nodes.indices;
    for ni = 1:numel(nix)
        nd = FullTree.select(nix(ni));
        ln = double(nd.lineno);
        % 体语句可能和 case/otherwise 同行（逗号分隔写法），用 >= 而非 >
        if ln >= fromLine && ln < toLine
            stmts(end+1) = string(join(split(char(strtrim(lower(string(nd.tree2str))))))); %#ok<AGROW>
        end
    end
end

sig = char(strjoin(stmts, "||"));
end





