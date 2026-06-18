function issues = mlint_singleUseVariable(filePath)
%mlint_singleUseVariable 基于 mtree + digraph 的单次使用检测。
% 规则：
%  1) 赋值后可达范围内零引用 -> 未使用
%  2) 赋值后可达范围内恰好一次引用 -> 仅使用一次

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

    fnIdx = FullTree.mtfind('Kind', 'FUNCTION').indices;

% 构建每行语句 kind（由 AST 节点反推，不做关键字字符串识别）
lineKindMap = dictionary;
iMarkLineKinds(FullTree, lineKindMap);

% 构建按变量聚合的引用计数（只统计 ID 读，不统计写）
refMap = collectReadRefs(FullTree);

for fi = 1:numel(funcs)
    fStart = funcs(fi).startLine;
    fEnd = funcs(fi).endLine;

    fnNode = [];
    for k = 1:numel(fnIdx)
        nd = FullTree.select(fnIdx(k));
        if double(nd.lineno) == fStart
            fnNode = nd;
            break;
        end
    end
    if isempty(fnNode)
        continue;
    end

    outputVars = iGetFunctionOutputs(fnNode);

    persistentVars = iGetPersistentVars(FullTree, fStart, fEnd);

    assignments = collectAssignments(FullTree, fStart, fEnd, true);
    if isempty(assignments)
        continue;
    end

    stmtLines = collectStmtLines(FullTree, fStart, fEnd, fEnd);
    if isempty(stmtLines)
        continue;
    end

    g = iBuildCfgDigraph(stmtLines, FullTree, lineKindMap);

    whileHeadVars = iCollectWhileHeadVars(FullTree, fStart, fEnd);

    allVars = unique(string({assignments.var}));
    for vi = 1:numel(allVars)
        varName = allVars(vi);
        if any(persistentVars == varName)
            continue;
        end
        isOutput = any(outputVars == varName);
        aIdx = find(string({assignments.var}) == varName);
        if isempty(aIdx)
            continue;
        end

        % 所有同名赋值行均可作为 blocker（BFS 在 blocker 处计数但阻断遍历）。
        % CFG 已负责跳过 if/else/switch 的兄弟分支，不在这里按文本分隔符排除。
        varAssignLines = unique([assignments(aIdx).line]);

        varLineMap = [];
        if isKey(refMap, char(varName))
            varLineMap = refMap(char(varName));
        end

        defUseLines = cell(1, numel(aIdx));
        useOwnerCount = dictionary;

        for ai = 1:numel(aIdx)
            a = assignments(aIdx(ai));
            % 保留赋值行之后的可达行 + 循环回边可达的早前行
            reach = iReachableWithoutRedef(g, a.line, fEnd, varAssignLines(varAssignLines ~= a.line));
            useLines = iIntersectRefLines(varLineMap, reach(reach ~= a.line & reach <= fEnd));
            defUseLines{ai} = useLines;

            for ui = 1:numel(useLines)
                ln = useLines(ui);
                % while 循环头读变量：循环体内对同变量的 def 不计入 owner count
                skipOwner = false;
                if isKey(whileHeadVars, ln)
                    whv = whileHeadVars(ln);
                    if ~isempty(whv) && any(whv == string(varName)) ...
                            && iIsInsideBlock(FullTree, a.line, ln, 'WHILE')
                        skipOwner = true;
                    end
                end
                if ~skipOwner
                    if isKey(useOwnerCount, ln)
                        useOwnerCount(ln) = useOwnerCount(ln) + 1;
                    else
                        useOwnerCount(ln) = 1;
                    end
                end
            end
        end

        for ai = 1:numel(aIdx)
            a = assignments(aIdx(ai));

            blockers = varAssignLines(varAssignLines ~= a.line);
            useLines = defUseLines{ai};

            [occ, firstUse] = iCountRefsOnLines(varLineMap, useLines);

            if isempty(useLines)
                if isOutput && iDefReachesFunctionExitWithoutRedef(g, a.line, blockers, fEnd, lineKindMap)
                    continue;
                end
                issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                    filePath, a.line, "mlint_singleUseVariable", ...
                    sprintf('变量"%s"已赋值但未使用', varName)}; %#ok<AGROW>
            elseif occ == 1
                % 若唯一引用行被其他 def 共享，或为输出变量出口，或仅用作下标 → 豁免
                if (isKey(useOwnerCount, firstUse) && useOwnerCount(firstUse) > 1) ...
                        || (isOutput && iDefReachesFunctionExitWithoutRedef(g, a.line, blockers, fEnd, lineKindMap)) ...
                        || iOnlyUseIsParenIndexing(FullTree, char(varName), firstUse) ...
                        || iIsOperatorRhsWithDotUse(FullTree, char(varName), a.line, firstUse)
                    continue;
                end
                if iIsMustUseWithoutRedef(g, a.line, firstUse, blockers, fEnd)
                    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                        filePath, a.line, "mlint_singleUseVariable", ...
                        sprintf('变量"%s"赋值后仅使用一次（第 %d 行），建议内联', varName, firstUse)}; %#ok<AGROW>
                end
            end
        end
    end
end

issues = table(issuesBuilder);
end

function iMarkLineKinds(FullTree, lineKindMap)
kinds = [ ...
    "IF", "ELSEIF", "ELSE", "FOR", "PARFOR", "WHILE", "SWITCH", ...
    "CASE", "OTHERWISE", "TRY", "CATCH", "RETURN", "BREAK", "CONTINUE", ...
    "EQUALS", "EXPR", "FUNCTION", "END"];

for ki = 1:numel(kinds)
    nodes = FullTree.mtfind('Kind', kinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        if ~isKey(lineKindMap, double(nd.lineno))
            lineKindMap(double(nd.lineno)) = char(kinds(ki));
        end
    end
end
end

function tf = iOnlyUseIsParenIndexing(FullTree, varName, useLine)
tf = false;
ix = FullTree.mtfind('Kind', 'ID').indices;
if isempty(ix)
    return;
end

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    try
        if double(nd.lineno) ~= useLine || string(nd.string) ~= string(varName)
            continue;
        end
        p = Parent(nd);
        if count(p) > 0 && strcmp(char(p.kind), 'SUBSCR')
            tf = true;
            return;
        end
    catch
    end
end
end

function tf = iIsOperatorRhsWithDotUse(FullTree, varName, assignLine, useLine)
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
    if double(nd.lineno) ~= assignLine
        continue;
    end
    lhs = Left(nd);
    if count(lhs) ~= 1 || string(lhs.string) ~= varName
        continue;
    end
    rhs = Right(nd);
    k = char(rhs.kind);
    if ~ismember(k, ["OR","AND","SHORTOR","SHORTAND","PLUS","MINUS","MUL","DIV", ...
            "LDIV","DOTMUL","DOTDIV","DOTLDIV","EXP","DOTEXP","EQ","NE", ...
            "LT","GT","LE","GE","COLON"])
        return;
    end
    % 检查引用处：唯一使用行为 useLine，变量 varName 的父节点是否为 DOT
    ids = FullTree.mtfind('Kind', 'ID');
    if count(ids) == 0
        return;
    end
    iix = ids.indices;
    for j = 1:numel(iix)
        idNd = FullTree.select(iix(j));
        if double(idNd.lineno) == useLine && string(idNd.string) == varName
            p = Parent(idNd);
            if count(p) > 0 && strcmp(char(p.kind), 'DOT')
                tf = true;
                return;
            end
        end
    end
end
end

function assignments = iCollectAssignments(FullTree, fStart, fEnd)
builder = MATLAB.DataTypes.ArrayBuilder();

ix = FullTree.mtfind('Kind', 'EQUALS').indices;
if isempty(ix)
    assignments = struct('line', {}, 'var', {}, 'isSelfRef', {});
    return;
end

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    ln = double(nd.lineno);
    if ln < fStart || ln > fEnd
        continue;
    end

    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
        continue;
    end

    varName = string(lhs.string);
    if strlength(varName) == 0
        continue;
    end
    isSelfRef = iTreeContainsSelfRef(Right(nd), FullTree, varName);
    % 循环控制标记：while 头读该变量，且当前赋值是常量（true/false），视为自引用
    if ~isSelfRef
        isSelfRef = iIsLoopControlFlagAssign(FullTree, nd, varName);
    end
    builder.Append(struct('line', ln, 'var', char(varName), 'isSelfRef', isSelfRef, 'rhsKind', char(Right(nd).kind)));
end

if isempty(builder.Harvest())
    assignments = struct('line', {}, 'var', {}, 'isSelfRef', {}, 'rhsKind', {});
else
    assignments = builder.Harvest();
end
end

% -------------------------------------------------------------------------
function tf = iTreeContainsSelfRef(node, FullTree, varName)
% 递归遍历 RHS 子树，检查是否包含对 varName 的自引用。
tf = false;
if count(node) == 0
    return;
end
k = char(node.kind);
if k == "ID"
    if string(node.string) == varName
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
function whileHeadVars = iCollectWhileHeadVars(FullTree, fStart, fEnd)
% 收集 while 头条件中读取的变量名，key=while头行号，value=变量名数组。
whileHeadVars = dictionary;
ix = FullTree.mtfind('Kind', 'WHILE').indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    ln = double(nd.lineno);
    if ln < fStart || ln > fEnd
        continue;
    end
    % while 条件的 ID 引用（不包含写入）
    ids = List(Left(nd)).mtfind('Kind', 'ID');
    if count(ids) == 0
        continue;
    end
    vars = strings(0, 1);
    iix = ids.indices;
    for ki = 1:numel(iix)
        vars(end + 1) = string(FullTree.select(iix(ki)).string); %#ok<AGROW>
    end
    if ~isempty(vars)
        whileHeadVars(ln) = unique(vars);
    end
end
end

function tf = iIsInsideBlock(FullTree, defLine, headLine, ix)
% 检查 defLine 是否在指定控制块内部（头行之后、匹配 end 之前）
tf = false;
ix = FullTree.mtfind('Kind', ix).indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if double(nd.lineno) ~= headLine
        continue;
    end
    [endL, ~] = pos2lc(nd, righttreepos(nd));
    tf = defLine > headLine && defLine <= endL;
    return;
end
end

% -------------------------------------------------------------------------
function tf = iIsLoopControlFlagAssign(FullTree, p, varName)
% 检查是否为 while 循环内的控制标记赋值（如 changed = false）
tf = false;
p = Parent(p);
while count(p) > 0
    if char(p.kind) == "WHILE"
        condIDs = List(Left(p)).mtfind('Kind', 'ID');
        if count(condIDs) == 0
            return;
        end
        cix = condIDs.indices;
        for ki = 1:numel(cix)
            if string(FullTree.select(cix(ki)).string) == varName
                tf = true;
                return;
            end
        end
        return;
    end
    p = Parent(p);
end
end

% -------------------------------------------------------------------------
function pv = iGetPersistentVars(FullTree, fStart, fEnd)
pv = strings(0, 1);
ix = FullTree.mtfind('Kind', 'PERSISTENT').indices;
if isempty(ix)
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    ln = double(nd.lineno);
    if ln < fStart || ln > fEnd
        continue;
    end
    % Arg → ID, 然后 Next → ID, Next → ID ... 链
    cur = Arg(nd);
    while count(cur) > 0
        if strcmp(char(cur.kind), 'ID')
            pv(end + 1) = string(cur.string); %#ok<AGROW>
        end
        try
            cur = Next(cur);
        catch
            break;
        end
    end
end
pv = unique(pv);
end

function outVars = iGetFunctionOutputs(outs)
outVars = strings(0, 1);
outs = Outs(outs);
if count(outs) == 0
    return;
end

if count(outs) == 1 && strcmp(char(outs.kind), 'LB')
    cur = Arg(outs);
else
    cur = outs;
end

while count(cur) > 0
    if strcmp(char(cur.kind), 'ID')
        s = strtrim(string(cur.string));
        if strlength(s) > 0
            outVars(end + 1) = s; %#ok<AGROW>
        end
    end
    try
        cur = Next(cur);
    catch
        break;
    end
end
end

function stmtLines = iBuildStatementLines(assignments, refMap, fStart, fEnd, lineKindMap, FullTree)
stmtLineBuffer = double([assignments.line]);
stmtLineBuffer(end + 1) = fEnd;

keys = refMap.keys;
for i = 1:numel(keys)
    k = refMap(keys{i}).keys;
    if ~isempty(k)
        stmtLineBuffer = [stmtLineBuffer, [k{:}]]; %#ok<AGROW>
    end
end

ctrlKeys = lineKindMap.keys;
for i = 1:numel(ctrlKeys)
    ln = ctrlKeys{i};
    if ln >= fStart && ln <= fEnd
        stmtLineBuffer(end + 1) = ln; %#ok<AGROW>
    end
end

% mtree 不产出 END 节点，需从控制块头用 righttreepos 推断 end 行
ctrlKinds = ["IF","SWITCH","FOR","PARFOR","WHILE","TRY"];
for ki = 1:numel(ctrlKinds)
    nodes = FullTree.mtfind('Kind', ctrlKinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for ii = 1:numel(ix)
        nd = FullTree.select(ix(ii));
        [endL, ~] = pos2lc(nd, righttreepos(nd));
        if endL >= fStart && endL <= fEnd
            stmtLineBuffer(end + 1) = endL; %#ok<AGROW>
        end
    end
end

stmtLines = unique(stmtLineBuffer);
stmtLines = stmtLines(stmtLines >= fStart & stmtLines <= fEnd);
end

function g = iBuildCfgDigraph(MissingNodes, FullTree, lineKindMap)
if numel(MissingNodes) <= 1
    if isempty(MissingNodes)
        g = digraph;
    else
        g = addnode(digraph, string(MissingNodes));
    end
    return;
end

s = strings(0, 1);
edgeTargets = strings(0, 1);

    [ifFalseTarget, branchOwner, ifEnd, loopEnd, enclosingLoop, switchTargets, switchOwner, switchEnd, tryEnd] = iAnalyzeControlBlocks(MissingNodes, FullTree, lineKindMap);

for i = 1:numel(MissingNodes)
    from = MissingNodes(i);
    next = iNextStmtLine(MissingNodes, i);

    k = iKindAt(lineKindMap, from);
    if strcmp(k, 'RETURN')
        continue;
    end

    if strcmp(k, 'TRY')
        % TRY → 第一句 try 体
        if next > 0
            s(end + 1) = string(from); %#ok<AGROW>
            edgeTargets(end + 1) = string(next); %#ok<AGROW>
        end
        % TRY → CATCH（异常路径）
        key = char(string(from));
        if isKey(ifFalseTarget, key)
            catchLine = ifFalseTarget(key);
            if catchLine > 0
                s(end + 1) = string(from); %#ok<AGROW>
                edgeTargets(end + 1) = string(catchLine); %#ok<AGROW>
            end
        end
        continue;
    end

    if strcmp(k, 'CATCH')
        % CATCH → 第一句 catch 体
        if next > 0
            s(end + 1) = string(from); %#ok<AGROW>
            edgeTargets(end + 1) = string(next); %#ok<AGROW>
        end
        continue;
    end

    if strcmp(k, 'IF') || strcmp(k, 'ELSEIF')
        % true-branch
        if next > 0
            s(end + 1) = string(from); %#ok<AGROW>
            edgeTargets(end + 1) = string(next); %#ok<AGROW>
        end
        % false-branch（elseif/else/if之后）
        key = char(string(from));
        if isKey(ifFalseTarget, key)
            falseTo = ifFalseTarget(key);
            if falseTo > 0
                s(end + 1) = string(from); %#ok<AGROW>
                edgeTargets(end + 1) = string(falseTo); %#ok<AGROW>
            end
        end
        continue;
    end

    if strcmp(k, 'FOR') || strcmp(k, 'PARFOR') || strcmp(k, 'WHILE')
        % loop true-branch: 进入循环体
        if next > 0
            s(end + 1) = string(from); %#ok<AGROW>
            edgeTargets(end + 1) = string(next); %#ok<AGROW>
        end
        % loop false-branch: 跳到循环后
        key = char(string(from));
        if isKey(loopEnd, key)
            falseTo = iNextStmtAfterLine(MissingNodes, loopEnd(key));
            if falseTo > 0
                s(end + 1) = string(from); %#ok<AGROW>
                edgeTargets(end + 1) = string(falseTo); %#ok<AGROW>
            end
        end
        continue;
    end

    if strcmp(k, 'SWITCH')
        key = char(string(from));
        if isKey(switchTargets, key)
            targets = switchTargets(key);
            for ti = 1:numel(targets)
                s(end + 1) = string(from); %#ok<AGROW>
                edgeTargets(end + 1) = string(targets(ti)); %#ok<AGROW>
            end
        end
        if isKey(switchEnd, key)
            afterEnd = iNextStmtAfterLine(MissingNodes, switchEnd(key));
            if afterEnd > 0
                s(end + 1) = string(from); %#ok<AGROW>
                edgeTargets(end + 1) = string(afterEnd); %#ok<AGROW>
            end
        end
        continue;
    end

    if strcmp(k, 'BREAK')
        key = char(string(from));
        if isKey(enclosingLoop, key)
            lsKey = char(string(enclosingLoop(key)));
            if isKey(loopEnd, lsKey)
                brTo = iNextStmtAfterLine(MissingNodes, loopEnd(lsKey));
                if brTo > 0
                    s(end + 1) = string(from); %#ok<AGROW>
                    edgeTargets(end + 1) = string(brTo); %#ok<AGROW>
                end
            end
        end
        continue;
    end

    if strcmp(k, 'CONTINUE')
        key = char(string(from));
        if isKey(enclosingLoop, key) && enclosingLoop(key) > 0
            s(end + 1) = string(from); %#ok<AGROW>
            edgeTargets(end + 1) = string(enclosingLoop(key)); %#ok<AGROW>
        end
        continue;
    end

    % 语句块末尾若下一行是 elseif/else，不应顺序落入分支头；应跳到 if 结束后。
    if next > 0
        nk = iKindAt(lineKindMap, next);
        if strcmp(nk, 'ELSEIF') || strcmp(nk, 'ELSE')
            nkKey = char(string(next));
            if isKey(branchOwner, nkKey)
                ownerKey = char(string(branchOwner(nkKey)));
                if isKey(ifEnd, ownerKey)
                    jumpTo = iSkipSiblingBranchHeaders(MissingNodes, lineKindMap, branchOwner, ifEnd, switchOwner, switchEnd, tryEnd, iNextStmtAfterLine(MissingNodes, ifEnd(ownerKey)));
                    if jumpTo > 0
                        s(end + 1) = string(from); %#ok<AGROW>
                        edgeTargets(end + 1) = string(jumpTo); %#ok<AGROW>
                    end
                    continue;
                end
            end
        end

        if strcmp(nk, 'CATCH')
            % try 体末尾遇到 CATCH → 跳到 try 块后
            nkKey = char(string(next));
            if isKey(branchOwner, nkKey)
                ownerKey = char(string(branchOwner(nkKey)));
                if isKey(tryEnd, ownerKey)
                    jumpTo = iSkipSiblingBranchHeaders(MissingNodes, lineKindMap, branchOwner, ifEnd, switchOwner, switchEnd, tryEnd, iNextStmtAfterLine(MissingNodes, tryEnd(ownerKey)));
                    if jumpTo > 0
                        s(end + 1) = string(from); %#ok<AGROW>
                        edgeTargets(end + 1) = string(jumpTo); %#ok<AGROW>
                    end
                    continue;
                end
            end
        end

        if strcmp(nk, 'CASE') || strcmp(nk, 'OTHERWISE')
            nkKey = char(string(next));
            if isKey(switchOwner, nkKey)
                swKey = char(string(switchOwner(nkKey)));
                if isKey(switchEnd, swKey)
                    jumpTo = iSkipSiblingBranchHeaders(MissingNodes, lineKindMap, branchOwner, ifEnd, switchOwner, switchEnd, tryEnd, iNextStmtAfterLine(MissingNodes, switchEnd(swKey)));
                    if jumpTo > 0
                        s(end + 1) = string(from); %#ok<AGROW>
                        edgeTargets(end + 1) = string(jumpTo); %#ok<AGROW>
                    end
                    continue;
                end
            end
        end

        % 循环体内节点不创建跳出循环的默认边
        key = char(string(from));
        if isKey(enclosingLoop, key)
            lsKey = char(string(enclosingLoop(key)));
            if isKey(loopEnd, lsKey)
                afterLoop = iNextStmtAfterLine(MissingNodes, loopEnd(lsKey));
                if afterLoop > 0 && next >= afterLoop
                    continue;
                end
            end
        end

        s(end + 1) = string(from); %#ok<AGROW>
        edgeTargets(end + 1) = string(next); %#ok<AGROW>
    end
end

% 循环回边：最后一个循环体行跳回循环头
loopKeys = loopEnd.keys;
for ki = 1:numel(loopKeys)
    sKey = loopKeys{ki};
    startLine = str2double(sKey);
    bodyLines = MissingNodes(MissingNodes >= startLine & MissingNodes <= loopEnd(sKey));
    if numel(bodyLines) >= 2
        s(end + 1) = string(bodyLines(end)); %#ok<AGROW>
        edgeTargets(end + 1) = string(startLine); %#ok<AGROW>
    end
end

g = digraph(s, edgeTargets);
MissingNodes = string(MissingNodes);
MissingNodes(ismember(MissingNodes, g.Nodes.Name)) = [];
if ~isempty(MissingNodes)
    g = addnode(g, MissingNodes);
end
end

function [ifFalseTarget, branchOwner, ifEnd, loopEnd, enclosingLoop, switchTargets, switchOwner, switchEnd, tryEnd] = iAnalyzeControlBlocks(stmtLines, FullTree, lineKindMap)
ifFalseTarget = dictionary;
branchOwner = dictionary;
ifEnd = dictionary;
loopEnd = dictionary;
enclosingLoop = dictionary;
switchTargets = dictionary;
switchOwner = dictionary;
switchEnd = dictionary;
tryEnd = dictionary;

% 从 AST 推断每个控制块的 end 行
blockEnd = dictionary;
ctrlKinds = ["IF","SWITCH","FOR","PARFOR","WHILE","TRY"];
for ki = 1:numel(ctrlKinds)
    nodes = FullTree.mtfind('Kind', ctrlKinds(ki));
    if count(nodes) == 0
        continue;
    end
    ix = nodes.indices;
    for ii = 1:numel(ix)
        nd = FullTree.select(ix(ii));
        startLn = double(nd.lineno);
        blockEnd(startLn) = findBlockEndLine(nd);
    end
end

% 预填充 loopEnd/switchEnd/tryEnd
endKeys = blockEnd.keys;
for ki = 1:numel(endKeys)
    startLn = endKeys{ki};
    k = iKindAt(lineKindMap, startLn);
    if strcmp(k, 'FOR') || strcmp(k, 'PARFOR') || strcmp(k, 'WHILE')
        sKey = char(string(startLn));
        loopEnd(sKey) = blockEnd(startLn);
    end
    if strcmp(k, 'SWITCH')
        sKey = char(string(startLn));
        switchEnd(sKey) = blockEnd(startLn);
    end
    if strcmp(k, 'TRY')
        sKey = char(string(startLn));
        tryEnd(sKey) = blockEnd(startLn);
    end
end

stack = struct('kind', {}, 'start', {}, 'ifHeaders', {}, 'elseLine', {}, 'caseLines', {});

for i = 1:numel(stmtLines)
    ln = stmtLines(i);
    k = iKindAt(lineKindMap, ln);

    % 弹出所有已越过出口的控制块
    while ~isempty(stack)
        topStart = stack(end).start;
        if isKey(blockEnd, topStart) && ln > blockEnd(topStart)
            blk = stack(end);
            stack(end) = [];
            if strcmp(blk.kind, 'IF')
                afterEnd = ln;
                ifEnd(char(string(blk.start))) = blockEnd(blk.start);
                hs = blk.ifHeaders;
                for h = 1:numel(hs)
                    thisIf = hs(h);
                    if h < numel(hs)
                        falseTo = hs(h + 1);
                    elseif blk.elseLine > 0
                        falseTo = blk.elseLine;
                    else
                        falseTo = afterEnd;
                    end
                    ifFalseTarget(char(string(thisIf))) = falseTo;
                    if numel(hs) > 1
                        branchOwner(char(string(thisIf))) = blk.start;
                    end
                end
            end
            if strcmp(blk.kind, 'LOOP')
                sKey = char(string(blk.start));
                loopEnd(sKey) = blockEnd(blk.start);
            end
            if strcmp(blk.kind, 'SWITCH')
                sKey = char(string(blk.start));
                switchEnd(sKey) = blockEnd(blk.start);
                switchTargets(sKey) = blk.caseLines;
            end
            if strcmp(blk.kind, 'TRY')
                sKey = char(string(blk.start));
                tryEnd(sKey) = blockEnd(blk.start);
            end
        else
            break;
        end
    end

    topLoop = iTopLoopStart(stack);
    if topLoop > 0
        enclosingLoop(char(string(ln))) = topLoop;
    end

    if strcmp(k, 'IF')
        blk.kind = 'IF';
        blk.start = ln;
        blk.ifHeaders = ln;
        blk.elseLine = 0;
        blk.caseLines = [];
        stack(end + 1) = blk; %#ok<AGROW>
        continue;
    end

    if strcmp(k, 'ELSEIF')
        if ~isempty(stack) && strcmp(stack(end).kind, 'IF')
            stack(end).ifHeaders(end + 1) = ln;
            branchOwner(char(string(ln))) = stack(end).start;
        end
        continue;
    end

    if strcmp(k, 'ELSE')
        if ~isempty(stack) && strcmp(stack(end).kind, 'IF')
            stack(end).elseLine = ln;
            branchOwner(char(string(ln))) = stack(end).start;
        end
        continue;
    end

    if strcmp(k, 'CASE') || strcmp(k, 'OTHERWISE')
        if ~isempty(stack) && strcmp(stack(end).kind, 'SWITCH')
            stack(end).caseLines(end + 1) = ln;
            switchOwner(char(string(ln))) = stack(end).start;
        end
        continue;
    end

    if strcmp(k, 'CATCH')
        if ~isempty(stack) && strcmp(stack(end).kind, 'TRY')
            % TRY→CATCH 作为 false-branch（异常路径）
            ifFalseTarget(char(string(stack(end).start))) = ln;
            branchOwner(char(string(ln))) = stack(end).start;
        end
        continue;
    end

    if strcmp(k, 'FOR') || strcmp(k, 'PARFOR') || strcmp(k, 'WHILE') || ...
            strcmp(k, 'SWITCH') || strcmp(k, 'TRY')
        if strcmp(k, 'FOR') || strcmp(k, 'PARFOR') || strcmp(k, 'WHILE')
            blk.kind = 'LOOP';
        else
            blk.kind = char(k);
        end
        blk.start = ln;
        blk.ifHeaders = [];
        blk.elseLine = 0;
        blk.caseLines = [];
        stack(end + 1) = blk; %#ok<AGROW>
        continue;
    end

    % FUNCTION 不作为控制块，FUNCTION 的 END 不需要建边
end

% 弹出所有未关闭的控制块（文件末尾关闭）
while ~isempty(stack)
    blk = stack(end);
    stack(end) = [];
    endLine = stmtLines(end);
    if strcmp(blk.kind, 'IF')
        afterEnd = endLine + 1;
        ifEnd(char(string(blk.start))) = endLine;
        hs = blk.ifHeaders;
        for h = 1:numel(hs)
            thisIf = hs(h);
            if h < numel(hs)
                falseTo = hs(h + 1);
            elseif blk.elseLine > 0
                falseTo = blk.elseLine;
            else
                falseTo = afterEnd;
            end
            ifFalseTarget(char(string(thisIf))) = falseTo;
            if numel(hs) > 1
                branchOwner(char(string(thisIf))) = blk.start;
            end
        end
    end
    if strcmp(blk.kind, 'LOOP')
        sKey = char(string(blk.start));
        loopEnd(sKey) = endLine;
    end
    if strcmp(blk.kind, 'SWITCH')
        sKey = char(string(blk.start));
        switchEnd(sKey) = endLine;
        switchTargets(sKey) = blk.caseLines;
    end
    if strcmp(blk.kind, 'TRY')
        sKey = char(string(blk.start));
        tryEnd(sKey) = endLine;
    end
end
end

function startLine = iTopLoopStart(stack)
startLine = 0;
for i = numel(stack):-1:1
    if strcmp(stack(i).kind, 'LOOP')
        startLine = stack(i).start;
        return;
    end
end
end

function k = iKindAt(lineKindMap, ln)
k = '';
if isKey(lineKindMap, ln)
    k = lineKindMap(ln);
end
end

function next = iNextStmtLine(stmtLines, i)
next = 0;
if i < numel(stmtLines)
    next = stmtLines(i + 1);
end
end

function next = iNextStmtAfterLine(stmtLines, idx)
next = 0;
idx = find(stmtLines > idx, 1, 'first');
if ~isempty(idx)
    next = stmtLines(idx);
end
end

function ln = iSkipSiblingBranchHeaders(stmtLines, lineKindMap, branchOwner, ifEnd, switchOwner, switchEnd, tryEnd, ln)
while ln > 0
    k = iKindAt(lineKindMap, ln);
    key = char(string(ln));
    if (strcmp(k, 'ELSEIF') || strcmp(k, 'ELSE')) && isKey(branchOwner, key)
        ownerKey = char(string(branchOwner(key)));
        if isKey(ifEnd, ownerKey)
            nextLn = iNextStmtAfterLine(stmtLines, ifEnd(ownerKey));
            if nextLn > 0 && nextLn ~= ln
                ln = nextLn;
                continue;
            end
        end
    elseif strcmp(k, 'CATCH') && isKey(branchOwner, key)
        ownerKey = char(string(branchOwner(key)));
        if isKey(tryEnd, ownerKey)
            nextLn = iNextStmtAfterLine(stmtLines, tryEnd(ownerKey));
            if nextLn > 0 && nextLn ~= ln
                ln = nextLn;
                continue;
            end
        end
    elseif (strcmp(k, 'CASE') || strcmp(k, 'OTHERWISE')) && isKey(switchOwner, key)
        ownerKey = char(string(switchOwner(key)));
        if isKey(switchEnd, ownerKey)
            nextLn = iNextStmtAfterLine(stmtLines, switchEnd(ownerKey));
            if nextLn > 0 && nextLn ~= ln
                ln = nextLn;
                continue;
            end
        end
    end
    break;
end
end

function reachable = iReachableWithoutRedef(g, startLine, UpperBound, blockers)
reachable = [];
if numnodes(g) == 0
    return;
end

startName = string(startLine);
if ~any(g.Nodes.Name == startName)
    return;
end

blocked = unique(blockers(:)');

startNode = find(g.Nodes.Name == startName, 1, 'first');
seen = false(1, numnodes(g));
q = startNode;
seen(startNode) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;

    ln = str2double(g.Nodes.Name(u));
    if ln <= UpperBound
        reachable(end + 1) = ln; %#ok<AGROW>
    end

    nbr = successors(g, u)';
    for v = nbr
        ln2 = str2double(g.Nodes.Name(v));
        if ln2 > UpperBound
            continue;
        end
        if ln2 ~= startLine && any(blocked == ln2)
            % blocker 参与引用计数（如自引用读旧值），但阻断继续遍历
            if ln2 <= UpperBound
                reachable(end + 1) = ln2; %#ok<AGROW>
            end
            continue;
        end
        if ~seen(v)
            seen(v) = true;
            q(end + 1) = v; %#ok<AGROW>
        end
    end
end

reachable = unique(reachable);
end

function MatchedLines = iIntersectRefLines(lineMap, candidates)
MatchedLines = zeros(1, 0);
if isempty(lineMap) || isempty(candidates)
    return;
end
for i = 1:numel(candidates)
    ln = candidates(i);
    if isKey(lineMap, ln)
        MatchedLines(end + 1) = ln; %#ok<AGROW>
    end
end
MatchedLines = unique(MatchedLines);
end

function tf = iDefReachesFunctionExitWithoutRedef(reach, assignLine, blockers, fEnd, lineKindMap)
tf = false;
reach = iReachableWithoutRedef(reach, assignLine, fEnd, blockers);
if isempty(reach)
    return;
end

if any(reach == fEnd)
    tf = true;
    return;
end

% 到达 return 语句的行也视为函数出口
for r = 1:numel(reach)
    if iKindAt(lineKindMap, reach(r)) == "RETURN"
        tf = true;
        return;
    end
end
end

function tf = iIsMustUseWithoutRedef(g, assignLine, useLine, blockers, UpperBound)
tf = false;
reach = iReachableWithoutRedef(g, assignLine, UpperBound, blockers);
if isempty(reach) || ~any(reach == useLine)
    return;
end

% 若 useLine 有多个入边（如循环回边+直线），赋值不支配引用 → 非 must-use
useIdx = find(g.Nodes.Name == string(useLine), 1, 'first');
if ~isempty(useIdx) && indegree(g, useIdx) > 1
    return;
end

tf = ~iExistsExitPathAvoidingUse(g, assignLine, reach, useLine, blockers);
end

function tf = iExistsExitPathAvoidingUse(g, assignLine, reachSet, useLine, blockers)
tf = false;
blocked = unique(blockers(:)');

startName = string(assignLine);
if ~any(g.Nodes.Name == startName)
    return;
end

startNode = find(g.Nodes.Name == startName, 1, 'first');
seen = false(1, numnodes(g));
q = startNode;
seen(startNode) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;
    succAll = successors(g, u)';
    succInReach = zeros(1, 0);
    succAllowed = zeros(1, 0);

    for v = succAll
        ln2 = str2double(g.Nodes.Name(v));
        if (ln2 ~= assignLine && any(blocked == ln2)) || ~any(reachSet == ln2)
            continue;
        end

        succInReach(end + 1) = v; %#ok<AGROW>
        if ln2 ~= useLine
            succAllowed(end + 1) = v; %#ok<AGROW>
        end
    end

    if isempty(succInReach)
        % 真正图出口（无后继者）才算避开
        if outdegree(g, u) == 0
            tf = true;
            return;
        end
        % 后继被阻塞（重定义等）≠ 出口，继续
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

function [occ, firstUse] = iCountRefsOnLines(lineMap, MatchedLines)
occ = 0;
firstUse = 0;
if isempty(lineMap)
    return;
end

MatchedLines = unique(MatchedLines);
for i = 1:numel(MatchedLines)
    ln = MatchedLines(i);
    if isKey(lineMap, ln)
        occ = occ + lineMap(ln);
        if firstUse == 0
            firstUse = ln;
        end
    end
end
end

