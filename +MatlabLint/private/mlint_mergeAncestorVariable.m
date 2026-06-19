function issues = mlint_mergeAncestorVariable(filePath)
%mlint_mergeAncestorVariable 检测可合并的祖先变量。
% 对于 A = expr 赋值，从 expr 中某变量 B 的每个定义点沿控制流向前搜索：
% 每条路径要么在遇到 A 之前到达函数结束，要么到达此 A = expr 赋值；若到达此赋值，则 B 此后不再出现。
% B 在到达目标赋值前可以被多次读取，这不影响“祖先变量”判断。

if nargin == 0
    issues = "若表达式右端某变量的全部定义路径要么在未遇到目标变量前结束，要么到达本行且此后不再使用该变量，建议合并为一个变量";
    return;
end

FullTree = List(mtree(filePath, '-file'));
funcs = MatlabLint.parseFunctions(filePath);
if isempty(funcs)
    issues = table(MATLAB.DataTypes.InsertiveTable());
    return;
end

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 预收集全局读引用 Map（stmt node idx -> count） ----
refMap = iCollectReadRefNodes(FullTree);

for fi = 1:numel(funcs)
    fnNode = funcs(fi).tree;

    % ---- CFG ----
    [stmtNodes, stmtKinds, stmtPos] = iCollectStmtNodesByNode(FullTree, fnNode);
    if isempty(stmtNodes)
        continue;
    end
    g = iBuildDigraphByNode(stmtNodes, stmtKinds, stmtPos);

    % ---- 输入参数 ----
    inputVars = iGetInputParams(fnNode);

    fnLeft = lefttreepos(fnNode);
    fnRight = righttreepos(fnNode);

    % ---- 收集所有简单赋值 A = expr ----
    eqs = FullTree.mtfind('Kind', 'EQUALS');
    if count(eqs) == 0
        continue;
    end
    eqIx = eqs.indices;

    for ei = 1:numel(eqIx)
        nd = FullTree.select(eqIx(ei));
        eqPos = lefttreepos(nd);
        if eqPos < fnLeft || righttreepos(nd) > fnRight
            continue;
        end
        lhs = Left(nd);
        if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
            continue;
        end
        A = string(lhs.string);
        if strlength(A) == 0
            continue;
        end

        % ---- 收集 expr 中引用但不在 LHS 出现的变量（排除 A） ----
        rhsVars = unique(collectRhsIds(Right(nd)));
        rhsVars(rhsVars == A) = [];

        for vi = 1:numel(rhsVars)
            B = rhsVars(vi);
            if ~isKey(refMap, char(B))
                continue;
            end
            bNodeMap = refMap(char(B));
            if ~iVarAppearsBeforeNode(bNodeMap, FullTree, eqPos)
                continue;
            end

            % ---- 收集 B 的赋值点（包括输入参数） ----
            bDefs = iCollectVarDefsNode(FullTree, eqIx, B, fnLeft, fnRight);
            if any(inputVars == B)
                bDefs(end + 1) = double(fnNode.indices); % 输入参数以函数入口节点作为虚拟定义
            end
            if isempty(bDefs) || iVarAppearsAfterNode(refMap, FullTree, B, eqPos, fnLeft, fnRight)
                continue;
            end

            % ---- 条件2：B 的每个赋值点都满足祖先变量控制流条件 ----
            allDominate = true;
            for di = 1:numel(bDefs)
                if ~iAllPathsReachTargetNode(g, stmtNodes, FullTree, bDefs(di), double(nd.indices), A, B, fnLeft, fnRight, refMap)
                    allDominate = false;
                    break;
                end
            end
            if ~allDominate
                continue;
            end

            % ---- 报告 ----
            ln = double(nd.lineno);
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, ln, ...
                "mlint_mergeAncestorVariable", ...
                sprintf('变量"%s"的全部定义路径要么在未遇到"%s"前结束，要么到达"%s"（第 %d 行）且此后不再出现，建议合并为一个变量', ...
                B, A, A, double(nd.lineno))}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function g = iBuildDigraphByNode(stmtNodes, stmtKinds, stmtPos)
% 构建简化 CFG：节点为 mtree 节点索引，边表示顺序控制流。
if numel(stmtNodes) <= 1
    g = digraph(string(stmtNodes), strings(0,1), strings(0,1));
    return;
end

edgesBuilder = MATLAB.DataTypes.InsertiveTable();
stack = struct('k', {}, 's', {}, 'ih', {}, 'el', {});
ifEnds = configureDictionary('double', 'double');
for i = 1:numel(stmtNodes)
    idx = stmtNodes(i);
    k = stmtKinds(i);

    while ~isempty(stack)
        top = stack(end);
        aft = iFindNextAfterNode(stmtPos, stmtNodes, ifEnds, top.s);
        if aft > 0 && stmtPos(i) >= stmtPos(aft)
            stack(end) = [];
        else
            break;
        end
    end

    if i < numel(stmtNodes)
        edgesBuilder(end+1, {'Source','Target'}) = {string(idx), string(stmtNodes(i+1))}; %#ok<AGROW>
    end

    if ismember(k, ["FUNCTION","IF","FOR","PARFOR","WHILE","SWITCH","TRY"])
        ifEnds(idx) = iFindBlockEndNode(stmtNodes, i);
    end
    if ismember(k, ["FOR","PARFOR","WHILE"])
        endNode = ifEnds(idx);
        if endNode > 0
            edgesBuilder(end+1, {'Source','Target'}) = {string(endNode), string(idx)}; %#ok<AGROW>
        end
    end
end

edges = table(edgesBuilder);
g = digraph(edges.Source, edges.Target);
if ~isempty(stmtNodes)
    nodes = string(stmtNodes);
    nodes(ismember(nodes, g.Nodes.Name)) = [];
    if ~isempty(nodes)
        g = addnode(g, nodes);
    end
end
end

% -------------------------------------------------------------------------
function vars = iGetInputParams(fnNode)
vars = MATLAB.Containers.Vector();
cur = Ins(fnNode);
while count(cur) > 0
    if strcmp(char(cur.kind), 'ID')
        vars.PushBack(string(cur.string));
    end
    try
        cur = Next(cur);
    catch
        break;
    end
end
vars = string(vars.Data(:));
end

% -------------------------------------------------------------------------
function refMap = iCollectReadRefNodes(FullTree)
refMap = configureDictionary('string', 'dictionary');
ix = FullTree.mtfind('Kind', 'ID').indices;
if isempty(ix)
    return;
end

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    name = char(nd.string);
    if isempty(name)
        continue;
    end

    p = Parent(nd);
    if count(p) > 0 && strcmp(char(p.kind), 'EQUALS')
        try
            if any(Left(p).indices == ix(i))
                continue;
            end
        catch
        end
    end

    nodeIdx = double(nd.indices);
    if ~isKey(refMap, name)
        refMap(name) = configureDictionary('double', 'double');
    end
    nodeMap = refMap(name);
    if isKey(nodeMap, nodeIdx)
        nodeMap(nodeIdx) = nodeMap(nodeIdx) + 1;
    else
        nodeMap(nodeIdx) = 1;
    end
    refMap(name) = nodeMap;
end
end

% -------------------------------------------------------------------------
function defs = iCollectVarDefsNode(FullTree, eqIx, varName, fnLeft, fnRight)
defs = MATLAB.Containers.Vector();
for i = 1:numel(eqIx)
    nd = FullTree.select(eqIx(i));
    if lefttreepos(nd) < fnLeft || righttreepos(nd) > fnRight
        continue;
    end
    lhs = Left(nd);
    if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == varName
        defs.PushBack(double(nd.indices));
    end
end
defs = double(defs.Data(:)');
end

% -------------------------------------------------------------------------
function tf = iVarAppearsBeforeNode(nodeMap, FullTree, afterPos)
tf = false;
keys = nodeMap.keys;
for ki = 1:numel(keys)
    nodeIdx = keys(ki);
    nd = FullTree.select(nodeIdx);
    if lefttreepos(nd) > afterPos && nodeMap(nodeIdx) > 0
        tf = true;
        return;
    end
end
end

% -------------------------------------------------------------------------
function tf = iVarAppearsAfterNode(refMap, FullTree, varName, afterPos, fnLeft, fnRight)
tf = false;
if ~isKey(refMap, char(varName))
    return;
end
nodeMap = refMap(char(varName));
keys = nodeMap.keys;
for ki = 1:numel(keys)
    nodeIdx = keys(ki);
    nd = FullTree.select(nodeIdx);
    if lefttreepos(nd) > afterPos && lefttreepos(nd) >= fnLeft && righttreepos(nd) <= fnRight && nodeMap(nodeIdx) > 0
        tf = true;
        return;
    end
end
end

% -------------------------------------------------------------------------
function tf = iAllPathsReachTargetNode(g, stmtNodes, FullTree, startNodeIdx, targetNodeIdx, A, B, fnLeft, fnRight, refMap)
persistent memo;
if isempty(memo)
    memo = configureDictionary('string', 'logical');
end
key = sprintf('%d_%d_%s_%s', startNodeIdx, targetNodeIdx, char(A), char(B));
if isKey(memo, key)
    tf = memo(key);
    return;
end

forbidden = iForbiddenNodes(FullTree, refMap, A, B, startNodeIdx, targetNodeIdx, fnLeft, fnRight);

start = find(stmtNodes == startNodeIdx, 1, 'first');
targetPos = find(stmtNodes == targetNodeIdx, 1, 'first');
if isempty(start) || isempty(targetPos)
    tf = false;
    memo(key) = tf;
    return;
end

seen = false(1, numel(stmtNodes));
q = start;
seen(start) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;
    nodeIdx = stmtNodes(u);

    succ = successors(g, string(nodeIdx))';
    if isempty(succ)
        if nodeIdx ~= targetNodeIdx
            tf = false;
            memo(key) = tf;
            return;
        end
        continue;
    end

    anyProceed = false;
    for v = succ
        succIdx = str2double(v);
        if any(forbidden == succIdx)
            continue;
        end
        anyProceed = true;
        vPos = find(stmtNodes == succIdx, 1, 'first');
        if ~isempty(vPos) && ~seen(vPos)
            seen(vPos) = true;
            q(end+1) = vPos; %#ok<AGROW>
        end
    end
    if ~anyProceed && nodeIdx ~= targetNodeIdx
        tf = false;
        memo(key) = tf;
        return;
    end
end

tf = true;
memo(key) = tf;
end

% -------------------------------------------------------------------------
function forbidden = iForbiddenNodes(FullTree, refMap, A, B, startNodeIdx, targetNodeIdx, fnLeft, fnRight)
builder = MATLAB.Containers.Vector();

eqs = FullTree.mtfind('Kind', 'EQUALS');
if count(eqs) > 0
    ix = eqs.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) < fnLeft || righttreepos(nd) > fnRight
            continue;
        end
        lhs = Left(nd);
        if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == A
            if double(nd.indices) ~= targetNodeIdx
                builder.PushBack(double(nd.indices));
            end
        end
        if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == B
            if double(nd.indices) ~= startNodeIdx && double(nd.indices) < targetNodeIdx
                builder.PushBack(double(nd.indices));
            end
        end
    end
end

if isKey(refMap, char(A))
    nodeMap = refMap(char(A));
    keys = nodeMap.keys;
    for ki = 1:numel(keys)
        nodeIdx = keys(ki);
        nd = FullTree.select(nodeIdx);
        if lefttreepos(nd) > lefttreepos(FullTree.select(startNodeIdx)) && double(nodeIdx) ~= targetNodeIdx
            builder.PushBack(double(nodeIdx));
        end
    end
end

forbidden = unique(double(builder.Data(:))');
end

% -------------------------------------------------------------------------
function [stmtNodes, stmtKinds, stmtPos] = iCollectStmtNodesByNode(FullTree, fnNode)
stmtKinds = ["FUNCTION","EQUALS","EXPR","IF","ELSEIF","ELSE","FOR","PARFOR","WHILE","SWITCH", ...
    "CASE","OTHERWISE","TRY","CATCH","RETURN","BREAK","CONTINUE"];
stmtNodes = zeros(1, 0);
stmtPos = zeros(1, 0);
fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);

for ki = 1:numel(stmtKinds)
    nodes = FullTree.mtfind('Kind', stmtKinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fnLeft && righttreepos(nd) <= fnRight
            stmtNodes(end+1) = ix(i); %#ok<AGROW>
            stmtPos(end+1) = lefttreepos(nd); %#ok<AGROW>
        end
    end
end

[stmtPos, order] = sort(stmtPos);
stmtNodes = stmtNodes(order);
stmtKinds = iStmtKindsForNodes(FullTree, stmtNodes, stmtKinds);
stmtNodes = unique(stmtNodes, 'stable');
stmtPos = stmtPos(1:numel(stmtNodes));
end

% -------------------------------------------------------------------------
function kinds = iStmtKindsForNodes(FullTree, stmtNodes, wantedKinds)
kinds = strings(1, numel(stmtNodes));
for i = 1:numel(stmtNodes)
    nd = FullTree.select(stmtNodes(i));
    k = string(nd.kind);
    if any(k == wantedKinds)
        kinds(i) = k;
    else
        kinds(i) = "EXPR";
    end
end
end

% -------------------------------------------------------------------------
function endNode = iFindBlockEndNode(stmtNodes, ownerPos)
endNode = 0;
ownerIdx = find(stmtNodes == ownerPos, 1, 'first');
if isempty(ownerIdx)
    return;
end
if ownerIdx < numel(stmtNodes)
    endNode = stmtNodes(ownerIdx + 1);
end
end

% -------------------------------------------------------------------------
function nextNode = iFindNextAfterNode(stmtPos, stmtNodes, ifEnds, ownerNodeIdx)
nextNode = 0;
if ~isKey(ifEnds, ownerNodeIdx)
    return;
end
endNode = ifEnds(ownerNodeIdx);
for i = 1:numel(stmtNodes)
    if stmtPos(i) > stmtPos(find(stmtNodes == endNode, 1, 'first'))
        nextNode = stmtNodes(i);
        return;
    end
end
end
