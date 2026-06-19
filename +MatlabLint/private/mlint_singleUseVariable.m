function issues = mlint_singleUseVariable(filePath)
%mlint_singleUseVariable 基于 mtree + digraph 的单次使用检测。
% 规则：
%  1) 赋值后可达范围内零引用 -> 未使用
%  2) 赋值后可达范围内恰好一次引用 -> 仅使用一次
% CFG 节点为 mtree 索引（不假设一行一节点，同一行可有多个控制流节点）。

if nargin == 0
    issues = "禁止一次性中间变量（赋值后仅用一次/从未使用）";
    return;
end

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

FullTree = List(mtree(filePath, '-file'));

funcs = MatlabLint.parseFunctions(filePath);
if isempty(funcs)
    issues = table(issuesBuilder);
    return;
end

% 按 mtree 节点索引收集所有变量的读引用（ID 节点索引数组）
readNodeIdx = iCollectVarReadNodes(FullTree);

for fi = 1:numel(funcs)
    fnNode = funcs(fi).tree;
    if isempty(fnNode)
        continue;
    end

    outputVars = iGetFunctionOutputs(fnNode);

    persistentVars = iGetPersistentVars(FullTree, fnNode);

    assignments = collectAssignments(FullTree, fnNode, true);
    if isempty(assignments)
        continue;
    end
    % 不转 string 会在下面比较处复现真实错误：
    % mlint_singleUseVariable:60, assignments.var == varName 的数据类型无效。
    assignments.var = assignments.var;

    [stmtNodes, stmtKinds] = iCollectStmtNodes(FullTree, fnNode);
    if isempty(stmtNodes)
        continue;
    end

    g = iBuildCfgDigraph(stmtNodes, stmtKinds, FullTree);
    if numnodes(g) == 0
        continue;
    end

    whileHeadVars = iCollectWhileHeadVars(FullTree, fnNode);

    allVars = unique(assignments.var);
    for vi = 1:numel(allVars)
        varName = allVars(vi);
        if any(persistentVars == varName)
            continue;
        end
        isOutput = any(outputVars == varName);
        aIdx = find(assignments.var == varName);
        if isempty(aIdx), continue; end

        % 该变量的 EQUALS 节点索引集合（mtree index）
        varEqIdxs = unique(assignments.eqIdx(aIdx));
        % 该变量的读引用 CFG 节点索引集（EXPR 祖先索引）
        readNodeIds = [];
        if isKey(readNodeIdx, varName)
            readNodeIdCell = readNodeIdx(varName);
            readNodeIds = readNodeIdCell{1};
        end

        useOwnerCount = configureDictionary('double', 'double');
        defUseNodes = cell(1, numel(aIdx));

        for ai = 1:numel(aIdx)
            aEqIdx = assignments.eqIdx(aIdx(ai));
            startNd = iEqIdxToCfgNode(FullTree, aEqIdx);
            otherEqs = varEqIdxs(varEqIdxs ~= aEqIdx);
            blockerNdsVec = MATLAB.Containers.Vector();
            for bi = 1:numel(otherEqs)
                if iAreSiblingEqNodes(FullTree, aEqIdx, otherEqs(bi)), continue; end
                blockerNdsVec.PushBack(iEqIdxToCfgNode(FullTree, otherEqs(bi)));
            end
            blockerNds = iVectorToDoubleRow(blockerNdsVec);

            reachNodes = iReachableWithoutRedef(g, startNd, 0, blockerNds);
            useNodeIds = intersect(reachNodes, readNodeIds);
            useNodeIds = setdiff(useNodeIds, startNd);
            defUseNodes{ai} = useNodeIds;

            for ui = 1:numel(useNodeIds)
                uid = useNodeIds(ui);
                skipOwner = false;
                if isKey(whileHeadVars, uid)
                    whvCell = whileHeadVars(uid);
                    whv = whvCell{1};
                    if ~isempty(whv) && any(whv == varName) ...
                            && iIsInsideBlock(FullTree, aEqIdx, uid, 'WHILE')
                        skipOwner = true;
                    end
                end
                if ~skipOwner
                    if isKey(useOwnerCount, uid)
                        useOwnerCount(uid) = useOwnerCount(uid) + 1;
                    else
                        useOwnerCount(uid) = 1;
                    end
                end
            end
        end

        for ai = 1:numel(aIdx)
            aLine = assignments.line(aIdx(ai));
            aEqIdx = assignments.eqIdx(aIdx(ai));
            if assignments.isSelfRef(aIdx(ai)), continue; end
            otherEqs = varEqIdxs(varEqIdxs ~= aEqIdx);
            blockerNdsVec = MATLAB.Containers.Vector();
            for bi = 1:numel(otherEqs)
                if iAreSiblingEqNodes(FullTree, aEqIdx, otherEqs(bi)), continue; end
                blockerNdsVec.PushBack(iEqIdxToCfgNode(FullTree, otherEqs(bi)));
            end
            blockerNds = iVectorToDoubleRow(blockerNdsVec);
            useNodeIds = defUseNodes{ai};
            occ = numel(useNodeIds);
            firstUseNode = 0;
            firstUseLine = 0;
            if ~isempty(useNodeIds)
                firstUseNode = useNodeIds(1);
                if firstUseNode > 0
                    try
                        firstUseLine = FullTree.select( firstUseNode ).lineno;
                    catch
                        firstUseLine = 0;
                    end
                end
            end

            if isempty(useNodeIds)
                if isOutput, continue; end
                if iDefReachesFunctionExitWithoutRedef(g, iEqIdxToCfgNode(FullTree, aEqIdx), blockerNds, stmtNodes(end), stmtNodes, stmtKinds)
                    continue;
                end
                issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                    filePath, aLine, "mlint_singleUseVariable", ...
                    sprintf('变量"%s"已赋值但未使用', varName)}; %#ok<AGROW>
            elseif occ == 1
                if firstUseNode == 0
                    continue;
                end
                if (isKey(useOwnerCount, firstUseNode) && useOwnerCount(firstUseNode) > 1) ...
                        || (isOutput && iDefReachesFunctionExitWithoutRedef(g, iEqIdxToCfgNode(FullTree, aEqIdx), blockerNds, stmtNodes(end), stmtNodes, stmtKinds)) ...
                        || iOnlyUseIsParenIndexing(FullTree, varName, firstUseNode) ...
                        || iIsOperatorRhsWithDotUse(FullTree, varName, aEqIdx, firstUseNode)
                    continue;
                end
                if iIsMustUseWithoutRedef(g, iEqIdxToCfgNode(FullTree, aEqIdx), iEqIdxToCfgNode(FullTree, aEqIdx), blockerNds)
                    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                        filePath, aLine, "mlint_singleUseVariable", ...
                        sprintf('变量"%s"赋值后仅使用一次（第 %d 行），建议内联', varName, firstUseLine)}; %#ok<AGROW>
                end
            end
        end
    end
end

issues = table(issuesBuilder);
end

% =========================================================================
function [stmtNodes, stmtKinds] = iCollectStmtNodes(FullTree, fnNode)
% 收集函数范围内的语句级 mtree 节点，按 lefttreepos 排序。
% 追加一个合成节点（索引为负值）作为函数出口。
% stmtNodes: mtree 索引数组（含合成索引）
% stmtKinds: 对应的 kind 字符串数组
stmtKinds = ["IF","ELSEIF","ELSE","FOR","PARFOR","WHILE","SWITCH", ...
    "CASE","OTHERWISE","TRY","CATCH","RETURN","BREAK","CONTINUE","EXPR"];
allIdx = [];
allKindsVec = MATLAB.Containers.Vector();
fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);

for ki = 1:numel(stmtKinds)
    nodes = FullTree.mtfind('Kind', stmtKinds(ki));
    if count(nodes) == 0, continue; end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if lefttreepos(nd) >= fnLeft && righttreepos(nd) <= fnRight
            allIdx(end+1) = ix(i); %#ok<AGROW>
            allKindsVec.PushBack(stmtKinds(ki));
        end
    end
end

% 按 lefttreepos 排序
positions = zeros(1, numel(allIdx));
for i = 1:numel(allIdx)
    nd = FullTree.select(allIdx(i));
    positions(i) = lefttreepos(nd);
end
[~, order] = sort(positions);
stmtNodes = allIdx(order);
allKinds = iVectorToStringCol(allKindsVec);
stmtKinds = allKinds(order);

% 追加合成函数出口节点（用负值确保不与任何真实 mtree 索引冲突）
exitIdx = -fnNode.indices * 100;
stmtNodes(end+1) = exitIdx; %#ok<AGROW>
stmtKinds(end+1) = "EXIT"; %#ok<AGROW>
end

% =========================================================================
function cfgNd = iEqIdxToCfgNode(FullTree, eqIdx)
% 从 EQUALS 节点索引找到其 EXPR 祖先（CFG 中的语句节点）
cfgNd = 0;
if eqIdx <= 0, return; end
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    if strcmp(par.kind, "EXPR")
        try, cfgNd = par.indices; catch, end
        return;
    end
    par = Parent(par);
end
end

function readIdx = iCollectVarReadNodes(FullTree)
% 返回 dictionary(varName → {stmtNodeIdx array})。
% 对每个读引用的 ID 节点，找到其最近的语句级祖先（EXPR 或 EQUALS）。
readIdx = configureDictionary('string', 'cell');
ix = FullTree.mtfind('Kind', 'ID').indices;
if isempty(ix), return; end
for i = 1:numel(ix)
    idNd = FullTree.select(ix(i));
    name = idNd.string;
    if isempty(name), continue; end
    % 排除写入（EQUALS 左侧的 ID）
    p = Parent(idNd);
    if count(p) > 0 && strcmp(p.kind, 'EQUALS')
        try
            if ismember(ix(i), Left(p).indices), continue; end
        catch
        end
    end
    % 找到最近的语句级祖先
    stmtNd = iFindStmtAncestor(FullTree, ix(i));
    if isempty(stmtNd) || stmtNd <= 0, continue; end
    if ~isKey(readIdx, name)
        readIdx(name) = {stmtNd};
    else
        arr = readIdx(name);
        arr = arr{1};
        arr(end+1) = stmtNd; %#ok<AGROW>
        readIdx(name) = {arr};
    end
end
end

function stmtIdx = iFindStmtAncestor(FullTree, idIdx)
% 从 ID 节点向上找第一个 CFG 语句级祖先（EXPR/IF/FOR/WHILE/SWITCH/TRY）
% IF/FOR/WHILE 条件中的读引用没有 EXPR 包装，需同样计入。
nd = FullTree.select(idIdx);
par = Parent(nd);
while count(par) > 0
    pk = par.kind;
    if ismember(pk, ["EXPR","IF","FOR","PARFOR","WHILE","SWITCH","TRY"])
        try
            stmtIdx = par.indices;
        catch
            stmtIdx = 0;
        end
        return;
    end
    par = Parent(par);
end
stmtIdx = 0;
end

% =========================================================================
function g = iBuildCfgDigraph(stmtNodes, stmtKinds, FullTree)
n = numel(stmtNodes);
if n == 0
    g = digraph;
    return;
end
if n == 1
    g = addnode(digraph, stmtNodes);
    return;
end

% blockEnd: mtree 索引 → 块结束后第一个语句节点的 mtree 索引
% jumpTarget: mtree 索引 → 假分支目标 mtree 索引
be = configureDictionary('double', 'double');
jt = configureDictionary('double', 'double');
el = configureDictionary('double', 'double');

% ---- 计算 blockEnd ----
ctrlKinds = ["IF","SWITCH","FOR","PARFOR","WHILE","TRY"];
for ki = 1:numel(ctrlKinds)
    for si = 1:n
        if stmtKinds(si) ~= ctrlKinds(ki), continue; end
        idx = stmtNodes(si);
        if idx < 0, continue; end % 合成节点跳过
        nd = FullTree.select(idx);
        ep = righttreepos(nd);
        % 找左边界 >= ep+1 的第一个语句节点
        aft = 0;
        for sj = 1:n
            snIdx = stmtNodes(sj);
            if snIdx < 0, continue; end
            if lefttreepos(FullTree.select(snIdx)) >= ep + 1
                aft = snIdx; break;
            end
        end
        be(idx) = aft;
    end
end

% ---- 栈式分析 jumpTarget ----
stack = struct('k',{},'s',{},'ih',{},'el',{});
for i = 1:n
    idx = stmtNodes(i); k = stmtKinds(i);
    if idx < 0, continue; end % 合成 EXIT 节点跳过

    % 弹出已越过的块
    while ~isempty(stack)
        ts = stack(end).s; aft = be(ts);
        if aft > 0 && lefttreepos(FullTree.select(idx)) >= lefttreepos(FullTree.select(aft))
            blk = stack(end); stack(end) = [];
            if strcmp(blk.k, 'IF')
                hs = blk.ih;
                for h = 1:numel(hs)
                    if h < numel(hs)
                        fn = hs(h+1);
                    elseif blk.el > 0
                        fn = blk.el;
                    else
                        fn = idx;
                    end
                    jt(hs(h)) = fn;
                end
            end
        else
            break;
        end
    end

    % 设置 enclosingLoop
    for si = numel(stack):-1:1
        if ismember(stack(si).k, ["LOOP"])
            el(idx) = stack(si).s; break;
        end
    end

    if ismember(k, ["FOR","PARFOR","WHILE"])
        blk.k = 'LOOP'; blk.s = idx; blk.ih = []; blk.el = 0;
        stack(end+1) = blk; %#ok<AGROW>
    elseif strcmp(k, 'IF')
        blk.k = 'IF'; blk.s = idx; blk.ih = idx; blk.el = 0;
        stack(end+1) = blk; %#ok<AGROW>
    elseif strcmp(k, 'ELSEIF') && ~isempty(stack) && strcmp(stack(end).k, 'IF')
        stack(end).ih(end+1) = idx; jt(idx) = stack(end).s;
    elseif strcmp(k, 'ELSE') && ~isempty(stack) && strcmp(stack(end).k, 'IF')
        stack(end).el = idx; jt(idx) = stack(end).s;
    elseif ismember(k, ["CASE","OTHERWISE"]) && ~isempty(stack)
        jt(idx) = stack(end).s;
    elseif strcmp(k, 'CATCH') && ~isempty(stack)
        jt(stack(end).s) = idx; jt(idx) = stack(end).s;
    elseif ismember(k, ["SWITCH","TRY"])
        blk.k = k; blk.s = idx; blk.ih = []; blk.el = 0;
        stack(end+1) = blk; %#ok<AGROW>
    end
end

% 弹出栈中剩余块
while ~isempty(stack)
    blk = stack(end); stack(end) = [];
    if strcmp(blk.k, 'IF')
        hs = blk.ih;
        for h = 1:numel(hs)
            if h < numel(hs)
                fn = hs(h+1);
            elseif blk.el > 0
                fn = blk.el;
            else
                fn = 0;
            end
            jt(hs(h)) = fn;
        end
    end
end

% 未解析的跳转目标（jt(idx)=0）重定向到 EXIT
exitIdx = stmtNodes(end); % EXIT 总是在最后
beKeys_all = be.keys;
for ki = 1:numel(beKeys_all)
    lh = beKeys_all(ki);
    if be(lh) == 0
        be(lh) = exitIdx;
    end
end
jtKeys_all = jt.keys;
for ki = 1:numel(jtKeys_all)
    jk = jtKeys_all(ki);
    if jt(jk) == 0
        jt(jk) = exitIdx;
    end
end

% ---- 建边 ----
sVec = MATLAB.Containers.Vector();
tVec = MATLAB.Containers.Vector();

for i = 1:n
    idx = stmtNodes(i); k = stmtKinds(i);
    if idx < 0, continue; end % EXIT 跳过

    if strcmp(k, 'RETURN'), continue; end

    if strcmp(k, 'BREAK')
        if isKey(el, idx)
            lh = el(idx);
            if isKey(be, lh) && be(lh) > 0
                sVec.PushBack(idx);
                tVec.PushBack(be( lh ));
            end
        end
        continue;
    end

    if strcmp(k, 'CONTINUE')
        if isKey(el, idx)
            sVec.PushBack(idx);
            tVec.PushBack(el( idx ));
        end
        continue;
    end

    if ismember(k, ["IF","ELSEIF"])
        if i < n
            sVec.PushBack(idx);
            tVec.PushBack(stmtNodes( i + 1 ));
        end
        if isKey(jt, idx) && jt(idx) > 0
            sVec.PushBack(idx);
            tVec.PushBack(jt( idx ));
        end
        continue;
    end

    if ismember(k, ["FOR","PARFOR","WHILE"])
        if i < n
            sVec.PushBack(idx);
            tVec.PushBack(stmtNodes( i + 1 ));
        end
        if isKey(be, idx) && be(idx) > 0
            sVec.PushBack(idx);
            tVec.PushBack(be( idx ));
        end
        continue;
    end

    if strcmp(k, 'SWITCH')
        if isKey(be, idx) && be(idx) > 0
            sVec.PushBack(idx);
            tVec.PushBack(be( idx ));
        end
        continue;
    end

    % 前驱若落入 elseif/else/case 分支头，跳到块后
    if i < n
        nk = stmtKinds(i+1);
        if ismember(nk, ["ELSEIF","ELSE","CASE","OTHERWISE"])
            if isKey(jt, stmtNodes(i+1))
                own = jt(stmtNodes(i+1));
                if isKey(be, own) && be(own) > 0
                    sVec.PushBack(idx);
                    tVec.PushBack(be( own ));
                    continue;
                end
            end
        end
    end

    % 默认顺序边
    if i < n
        sVec.PushBack(idx);
        tVec.PushBack(stmtNodes( i + 1 ));
    end
end

% 循环回边
beKeys = be.keys;
for ki = 1:numel(beKeys)
    lh = beKeys(ki);
    lhk = ''; for si = 1:n, if stmtNodes(si) == lh, lhk = stmtKinds(si); break; end; end
    if ~ismember(lhk, ["FOR","PARFOR","WHILE"]), continue; end
    aft = be(lh); if aft == 0, continue; end
    % 找最后一个循环体语句（在 lh 之后、aft 之前）
    bl = 0;
    for si = 1:n
        if stmtNodes(si) == aft, break; end
        if stmtNodes(si) > lh, bl = stmtNodes(si); end
    end
    if bl > 0
        sVec.PushBack(bl);
        tVec.PushBack(lh);
    end
end

s = iVectorToStringCol(sVec);
t = iVectorToStringCol(tVec);
g = digraph(s, t);
nnStr = stmtNodes;
nnStr(ismember(nnStr, g.Nodes.Name)) = [];
if ~isempty(nnStr), g = addnode(g, nnStr); end
end

function tf = iOnlyUseIsParenIndexing(FullTree, varName, useNodeIdx)
tf = false;
ix = FullTree.mtfind('Kind', 'ID').indices;
if isempty(ix)
    return;
end

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    try
        if nd.indices ~= useNodeIdx || nd.string ~= varName
            continue;
        end
        p = Parent(nd);
        if count(p) > 0 && strcmp(p.kind, 'SUBSCR')
            tf = true;
            return;
        end
    catch
    end
end
end

function tf = iIsOperatorRhsWithDotUse(FullTree, varName, assignNodeIdx, useNodeIdx)
% 豁免场景：赋值右端为运算符表达式（如 ix = A | B | C），
% 且唯一引用处使用点索引（如 ix.indices）。运算符链无法直接接 .indices。
tf = false;

% 检查赋值处：EQUALS 节点的 RHS 是否为运算符
ix = FullTree.mtfind('Kind', 'EQUALS').indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if nd.indices ~= assignNodeIdx
        continue;
    end
    lhs = Left(nd);
    if count(lhs) ~= 1 || lhs.string ~= varName
        continue;
    end
    rhs = Right(nd);
    k = rhs.kind;
    if ~ismember(k, ["OR","AND","SHORTOR","SHORTAND","PLUS","MINUS","MUL","DIV", ...
            "LDIV","DOTMUL","DOTDIV","DOTLDIV","EXP","DOTEXP","EQ","NE", ...
            "LT","GT","LE","GE","COLON"])
        return;
    end
                % 检查引用处：唯一使用节点的父节点是否为 DOT
    ids = FullTree.mtfind('Kind', 'ID');
    if count(ids) == 0
        return;
    end
    iix = ids.indices;
    for j = 1:numel(iix)
        idNd = FullTree.select(iix(j));
        if idNd.indices == useNodeIdx && idNd.string == varName
            p = Parent(idNd);
            if count(p) > 0 && strcmp(p.kind, 'DOT')
                tf = true;
                return;
            end
        end
    end
end
end

% -------------------------------------------------------------------------
function tf = iTreeContainsSelfRef(node, FullTree, varName)
% 递归遍历 RHS 子树，检查是否包含对 varName 的自引用。
tf = false;
if count(node) == 0
    return;
end
k = node.kind;
if k == "ID"
    if node.string == varName
        tf = true;
    end
    return;
end

% 一元运算符：Arg
if ismember(k, ["NOT","UMINUS","UPLUS","TRANS","DOTTRANS"])
    if count(Arg(node)) > 0
        tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
    end
    return;
end

% 二元运算符：Left + Right
if ismember(k, ["PLUS","MINUS","MUL","DIV","LDIV","DOTMUL","DOTDIV","DOTLDIV", ...
               "EXP","DOTEXP","EQ","NE","LT","GT","LE","GE","AND","OR","SHORTAND","SHORTOR", ...
               "COLON","DOT"])
    if iTreeContainsSelfRef(Left(node), FullTree, varName)
        tf = true;
        return;
    end
    if count(Right(node)) > 0
        tf = iTreeContainsSelfRef(Right(node), FullTree, varName);
    end
    return;
end

% 下标/圆括号引用：Left 是被索引对象，Right 是索引列表
if k == "SUBSCR"
    if count(Left(node)) > 0 ...
            && iTreeContainsSelfRef(Left(node), FullTree, varName)
        tf = true;
        return;
    end
    if count(Right(node)) > 0
        tf = iTreeContainsSelfRef(Right(node), FullTree, varName);
    end
    return;
end

% 函数调用：遍历实参列表
if k == "CALL"
    % 函数名不检查（Left 是函数名）
    args = Right(node);
    if count(args) > 0
        tf = iTreeContainsSelfRef(args, FullTree, varName);
    end
    return;
end

% 容器类型：EXPR/PARENS/LB 单子节点(Arg)，ROW/CELL 链表(Next)
if ismember(k, ["EXPR","PARENS","LB"])
    if count(Arg(node)) > 0
        tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
    end
    return;
end

if ismember(k, ["ROW","CELL"])
    child = Arg(node);
    while count(child) > 0
        if iTreeContainsSelfRef(child, FullTree, varName)
            tf = true;
            return;
        end
        try
            child = Next(child);
        catch
            break;
        end
    end
    return;
end

% 通用回退：尝试 Left/Right/Arg
if (count(Left(node)) > 0 && iTreeContainsSelfRef(Left(node), FullTree, varName)) ...
        || (count(Right(node)) > 0 && iTreeContainsSelfRef(Right(node), FullTree, varName))
    tf = true;
    return;
end
if count(Arg(node)) > 0
    tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
end
end

% -------------------------------------------------------------------------
function whileHeadVars = iCollectWhileHeadVars(FullTree, fnNode)
% 收集 while 头条件中读取的变量名，key=while 节点索引，value=变量名数组。
whileHeadVars = configureDictionary('double', 'cell');
ix = FullTree.mtfind('Kind', 'WHILE').indices;
if isempty(ix)
    return;
end
fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if lefttreepos(nd) < fnLeft || righttreepos(nd) > fnRight
        continue;
    end
    % while 条件的 ID 引用（不包含写入）
    ids = List(Left(nd)).mtfind('Kind', 'ID');
    if count(ids) == 0
        continue;
    end
    vars = MATLAB.Containers.Vector();
    iix = ids.indices;
    for ki = 1:numel(iix)
        vars.PushBack(FullTree.select( iix( ki ) ).string);
    end
    vars = vars.Data( : );
    if ~isempty(vars)
        whileHeadVars(nd.indices) = {unique(vars)};
    end
end
end

function tf = iIsInsideBlock(FullTree, defNodeIdx, headNodeIdx, ix)
% 检查 defNodeIdx 是否在指定控制块内部（头节点之后、匹配 end 之前）
tf = false;
ix = FullTree.mtfind('Kind', ix).indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if nd.indices ~= headNodeIdx
        continue;
    end
    tf = lefttreepos(FullTree.select(defNodeIdx)) > lefttreepos(nd) ...
        && righttreepos(FullTree.select(defNodeIdx)) <= righttreepos(nd);
    return;
end
end

% -------------------------------------------------------------------------
function pv = iGetPersistentVars(FullTree, fnNode)
pvVec = MATLAB.Containers.Vector();
ix = FullTree.mtfind('Kind', 'PERSISTENT').indices;
if isempty(ix)
    pv = strings(0, 1);
    return;
end
fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if lefttreepos(nd) < fnLeft || righttreepos(nd) > fnRight
        continue;
    end
    % Arg → ID, 然后 Next → ID, Next → ID ... 链
    cur = Arg(nd);
    while count(cur) > 0
        if strcmp(cur.kind, 'ID')
            pvVec.PushBack(cur.string);
        end
        try
            cur = Next(cur);
        catch
            break;
        end
    end
end
pv = iVectorToStringCol(pvVec);
pv = unique(pv);
end

function outVars = iGetFunctionOutputs(outs)
outVars = MATLAB.Containers.Vector();
outs = Outs(outs);
if count(outs) == 0
    outVars = strings(0, 1);
    return;
end

if count(outs) == 1 && strcmp(outs.kind, 'LB')
    cur = Arg(outs);
else
    cur = outs;
end

while count(cur) > 0
    if strcmp(cur.kind, 'ID')
        s = strtrim(cur.string);
        if strlength(s) > 0
            outVars.PushBack(s);
        end
    end
    try
        cur = Next(cur);
    catch
        break;
    end
end
outVars = string(outVars.Data(:));
end

% =========================================================================
function reachNodes = iReachableWithoutRedef(g, startNodeIdx, ~, blockers)
% BFS from startNodeIdx (mtree index). Returns CFG node indices in reachable set.
% blockers are mtree indices that block traversal (counted but not expanded).
reachNodes = [];
if numnodes(g) == 0 || startNodeIdx <= 0, return; end

startName = startNodeIdx;
% 不转 string 会在节点名比较处复现真实错误：
% mlint_singleUseVariable:515 调用链中的 == 数据类型无效。
startName = startName;
if ~any(g.Nodes.Name == startName), return; end

blocked = unique(blockers(blockers > 0));

startU = find(g.Nodes.Name == startName, 1, 'first');
seen = false(1, numnodes(g));
q = startU;
seen(startU) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;

    nodeIdx = str2double(g.Nodes.Name(u));
    reachNodes(end + 1) = nodeIdx; %#ok<AGROW>

    nbr = successors(g, u)';
    for v = nbr
        nbrIdx = str2double(g.Nodes.Name(v));
        if nbrIdx ~= startNodeIdx && any(blocked == nbrIdx)
            reachNodes(end + 1) = nbrIdx; %#ok<AGROW>
            continue;
        end
        if ~seen(v), seen(v) = true; q(end + 1) = v; end %#ok<AGROW>
    end
end

reachNodes = unique(reachNodes);
end

% =========================================================================
function tf = iDefReachesFunctionExitWithoutRedef(g, startNodeIdx, blockerNds, exitNodeIdx, stmtNodes, stmtKinds)
tf = false;
if startNodeIdx <= 0, return; end
reachNodes = iReachableWithoutRedef(g, startNodeIdx, exitNodeIdx, blockerNds);
if isempty(reachNodes), return; end

% Check if any reachable node is the synthetic exit node or is RETURN
for i = 1:numel(reachNodes)
    if reachNodes(i) == exitNodeIdx
        tf = true; return;
    end
    pos = find(stmtNodes == reachNodes(i), 1);
    if ~isempty(pos) && stmtKinds(pos) == "RETURN"
        tf = true; return;
    end
end
end

% =========================================================================
function tf = iIsMustUseWithoutRedef(g, startNodeIdx, useNodeIdx, blockerNds)
tf = false;
if startNodeIdx <= 0 || useNodeIdx <= 0, return; end
reachNodes = iReachableWithoutRedef(g, startNodeIdx, inf, blockerNds);
if isempty(reachNodes) || ~any(reachNodes == useNodeIdx)
    return;
end

% 若唯一使用节点有多个入边（如循环回边+直线），赋值不支配引用 → 非 must-use
% 不转 string 会在该比较处复现真实错误：
% mlint_singleUseVariable 调用链中的 == 数据类型无效。
useIdx = find(g.Nodes.Name == useNodeIdx, 1, 'first');
if ~isempty(useIdx) && indegree(g, useIdx) > 1
    return;
end

tf = ~iExistsExitPathAvoidingUse(g, startNodeIdx, reachNodes, useNodeIdx, blockerNds);
end

% =========================================================================
function tf = iExistsExitPathAvoidingUse(g, startNodeIdx, reachSet, useNodeIdx, blockers)
tf = false;
blocked = unique(blockers(blockers > 0));

startName = startNodeIdx;
% 不转 string 会在节点名比较处复现真实错误：
% mlint_singleUseVariable 调用链中的 == 数据类型无效。
startName = startName;
if ~any(g.Nodes.Name == startName), return; end

startNode = find(g.Nodes.Name == startName, 1, 'first');
seen = false(1, numnodes(g));
q = startNode;
seen(startNode) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;
    succAll = successors(g, u)';
    succInReachVec = MATLAB.Containers.Vector();
    succAllowedVec = MATLAB.Containers.Vector();

    for v = succAll
        nbrIdx = str2double(g.Nodes.Name(v));
        if (nbrIdx ~= startNodeIdx && any(blocked == nbrIdx)) || ~any(reachSet == nbrIdx)
            continue;
        end
        succInReachVec.PushBack(v);
        if nbrIdx ~= useNodeIdx
            succAllowedVec.PushBack(v);
        end
    end

    succInReach = iVectorToDoubleRow(succInReachVec);
    succAllowed = iVectorToDoubleRow(succAllowedVec);

    if isempty(succInReach)
        if outdegree(g, u) == 0
            tf = true; return;
        end
        continue;
    end

    for v = succAllowed
        if ~seen(v)
            seen(v) = true;
            q(end + 1) = v; %#ok<AGROW>
        end
    end
end
end

% =========================================================================
function tf = iAreSiblingEqNodes(FullTree, eqIdx1, eqIdx2)
% 检查两个 EQUALS 节点是否在互斥兄弟分支中（if-else 或 try-catch）
tf = false;
if eqIdx1 <= 0 || eqIdx2 <= 0, return; end
if eqIdx1 == eqIdx2, return; end

ifAncestors1 = iCollectIfAncestors(FullTree, eqIdx1);
for a = 1:numel(ifAncestors1)
    if iIsInElseSubtree(FullTree, eqIdx2, ifAncestors1(a))
        tf = true; return;
    end
end

ifAncestors2 = iCollectIfAncestors(FullTree, eqIdx2);
for a = 1:numel(ifAncestors2)
    if iIsInElseSubtree(FullTree, eqIdx1, ifAncestors2(a))
        tf = true; return;
    end
end

tf = iAreTryCatchSiblings(FullTree, eqIdx1, eqIdx2);
end

% =========================================================================
function ifAncestors = iCollectIfAncestors(FullTree, eqIdx)
builder = MATLAB.Containers.Vector();
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    if strcmp(par.kind, 'IF')
        try, builder.PushBack(par.indices); catch, end
    end
    par = Parent(par);
end
ifAncestors = builder.Data( : );
end

% =========================================================================
function tf = iIsInElseSubtree(FullTree, eqIdx, ifIdx)
% 检查 eqIdx 节点是否在 ifIdx 的 ELSE 子树中。
% 注意：mtree 中 Parent(ELSE) 可能是 IFHEAD 而非 IF，需逐级上溯。
tf = false;
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    pk = par.kind;
    if strcmp(pk, 'IF')
        try
            if par.indices == ifIdx, return; end % 到达目标但未经过 ELSE
        catch
        end
    end
    if strcmp(pk, 'ELSE')
        % 从 ELSE 上溯直到找到其所属的 IF
        an = par;
        while count(an) > 0
            if strcmp(an.kind, 'IF')
                try
                    if an.indices == ifIdx
                        tf = true; return;
                    end
                catch
                end
                break; % 找到 ELSE 所属的 IF，但不是目标
            end
            an = Parent(an);
        end
    end
    par = Parent(par);
end
end


% =========================================================================
function tf = iAreTryCatchSiblings(FullTree, eqIdx1, eqIdx2)
tf = false;
anc1 = iCollectTryAncestors(FullTree, eqIdx1);
for a = 1:numel(anc1)
    if anc1(a).isCatch && iIsDescendantOfTry(FullTree, eqIdx2, anc1(a).tryIdx)
        tf = true; return;
    end
    if ~anc1(a).isCatch && iIsInCatchSubtree(FullTree, eqIdx2, anc1(a).tryIdx)
        tf = true; return;
    end
end
end

function ancs = iCollectTryAncestors(FullTree, eqIdx)
ancsRows = MATLAB.DataTypes.InsertiveTable();
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    pk = par.kind;
    if strcmp(pk, 'TRY')
        ancsRows(end+1, {'tryIdx','isCatch'}) = {par.indices, false};
    elseif strcmp(pk, 'CATCH')
        an = par;
        while count(an) > 0
            if strcmp(an.kind, 'TRY')
                ancsRows(end+1, {'tryIdx','isCatch'}) = {an.indices, true};
                break;
            end
            an = Parent(an);
        end
    end
    par = Parent(par);
end
ancsTable = table(ancsRows);
if isempty(ancsTable)
    ancs = struct('tryIdx', {}, 'isCatch', {});
else
    ancs = table2struct(ancsTable);
end
end

function tf = iIsDescendantOfTry(FullTree, eqIdx, tryIdx)
tf = false;
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    if strcmp(par.kind, 'CATCH'), return; end
    if strcmp(par.kind, 'TRY')
        try
            if par.indices == tryIdx, tf = true; return; end
        catch
        end
    end
    par = Parent(par);
end
end

function tf = iIsInCatchSubtree(FullTree, eqIdx, tryIdx)
tf = false;
nd = FullTree.select(eqIdx);
par = Parent(nd);
while count(par) > 0
    if strcmp(par.kind, 'CATCH')
        an = par;
        while count(an) > 0
            if strcmp(an.kind, 'TRY')
                try
                    if an.indices == tryIdx, tf = true; return; end
                catch
                end
                break;
            end
            an = Parent(an);
        end
    end
    if strcmp(par.kind, 'TRY')
        try
            if par.indices == tryIdx, return; end
        catch
        end
    end
    par = Parent(par);
end
end

% -------------------------------------------------------------------------
function arr = iVectorToDoubleRow(vec)
arr = vec.Data( : ).';
end

% -------------------------------------------------------------------------
function arr = iVectorToStringCol(vec)
% 不转 string 会在 digraph(s,t) 处复现真实错误：
% mlint_singleUseVariable:515, 目标节点必须为正整数索引数组（节点名类型不一致导致）。
arr = string(vec.Data(:));
end


