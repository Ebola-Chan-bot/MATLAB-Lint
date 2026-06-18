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

fnIdx = FullTree.mtfind('Kind', 'FUNCTION').indices;
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 预收集全局读引用 Map ----
refMap = collectReadRefs(FullTree);

for fi = 1:numel(funcs)
    fStart = funcs(fi).startLine;
    fEnd = funcs(fi).endLine;

    % ---- CFG ----
    stmts = collectStmtLines(FullTree, fStart, fEnd);
    if isempty(stmts)
        continue;
    end
    g = iBuildDigraph(stmts, FullTree);

    % ---- 输入参数 ----
    inputVars = iGetInputParams(FullTree, fStart, fnIdx);

    % ---- 收集所有简单赋值 A = expr ----
    eqs = FullTree.mtfind('Kind', 'EQUALS');
    if count(eqs) == 0
        continue;
    end
    eqIx = eqs.indices;

    for ei = 1:numel(eqIx)
        nd = FullTree.select(eqIx(ei));
        ln = double(nd.lineno);
        if ln < fStart || ln > fEnd
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
            % 检查本行是否真的有 B 的读引用
            bLineMap = refMap(char(B));
            if ~isKey(bLineMap, ln)
                continue;
            end

            % ---- 收集 B 的赋值点（包括输入参数） ----
            bDefs = iCollectVarDefs(FullTree, eqIx, B, fStart, fEnd);
            if any(inputVars == B)
                bDefs(end + 1) = fStart; % 输入参数以函数入口为虚拟定义
            end
            if isempty(bDefs) || iVarAppearsAfter(bLineMap, ln, fEnd, g)
                continue;
            end

            % ---- 条件2：B 的每个赋值点都满足祖先变量控制流条件 ----
            allDominate = true;
            for di = 1:numel(bDefs)
                if ~iAllPathsReachTarget(g, stmts, FullTree, bDefs(di), ln, A, B, fEnd, refMap)
                    allDominate = false;
                    break;
                end
            end
            if ~allDominate
                continue;
            end

            % ---- 报告 ----
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, ln, ...
                "mlint_mergeAncestorVariable", ...
                sprintf('变量"%s"的全部定义路径要么在未遇到"%s"前结束，要么到达"%s"（第 %d 行）且此后不再出现，建议合并为一个变量', ...
                B, A, A, ln)}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function g = iBuildDigraph(MissingNodes, FullTree)
% 构建简化 CFG：节点为行号，边表示顺序控制流。
if numel(MissingNodes) <= 1
    g = digraph(string(MissingNodes), strings(0,1), strings(0,1));
    return;
end
n = numel(MissingNodes);
s = strings(0,1);
t = strings(0,1);

% 连续行顺序边
for i = 1:n-1
    s(end+1) = string(MissingNodes(i));  %#ok<AGROW>
    t(end+1) = string(MissingNodes(i+1)); %#ok<AGROW>
end

% 分支跳转：IF/ELSEIF → 下一个 elseif/else/endif 之后
ifKeys = dictionary;
stack = [];
for i = 1:n
    ln = MissingNodes(i);
    k = iKindFromAst(FullTree, ln);
    if ismember(k, ["IF","FOR","PARFOR","WHILE","SWITCH","TRY"])
        stack(end+1) = ln; %#ok<AGROW>
        endL = iFindEnd(FullTree, ln);
        ifKeys(ln) = endL;
        % 循环：回边 + 假出口边
        if ismember(k, ["FOR","PARFOR","WHILE"])
            s(end+1) = string(endL); %#ok<AGROW>
            t(end+1) = string(ln); %#ok<AGROW>
            % 假出口：跳过整个循环体
            afterIdx = find(MissingNodes > endL, 1, 'first');
            if ~isempty(afterIdx)
                s(end+1) = string(ln); %#ok<AGROW>
                t(end+1) = string(MissingNodes(afterIdx)); %#ok<AGROW>
            end
        end
    elseif ismember(k, ["ELSEIF","ELSE","CASE","OTHERWISE","CATCH"])
        % 跳到对应 if/switch/try 的 end
        if ~isempty(stack)
            owner = stack(end);
            s(end+1) = string(ln); %#ok<AGROW>
            t(end+1) = string(ifKeys(owner)); %#ok<AGROW>
        end
    elseif k == "END"
        if ~isempty(stack) && ifKeys(stack(end)) == ln
            stack(end) = [];
        end
    end
end

g = digraph(s, t);
if ~isempty(MissingNodes)
    MissingNodes = string(MissingNodes);
    MissingNodes(ismember(MissingNodes, g.Nodes.Name)) = [];
    if ~isempty(MissingNodes)
        g = addnode(g, MissingNodes);
    end
end
end

% -------------------------------------------------------------------------
function endL = iFindEnd(FullTree, ln)
ix = FullTree.mtfind('Kind', 'IF') | FullTree.mtfind('Kind', 'FOR') | FullTree.mtfind('Kind', 'PARFOR') ...
    | FullTree.mtfind('Kind', 'WHILE') | FullTree.mtfind('Kind', 'SWITCH') | FullTree.mtfind('Kind', 'TRY');
ix = ix.indices;
if isempty(ix)
    endL = ln;
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if double(nd.lineno) == ln
        [endL, ~] = pos2lc(nd, righttreepos(nd));
        return;
    end
end
endL = ln;
end

% -------------------------------------------------------------------------
function k = iKindFromAst(FullTree, ln)
ix = FullTree.mtfind('Kind', 'IF');
for kind = ["ELSEIF", "ELSE", "FOR", "PARFOR", "WHILE", "SWITCH", ...
        "CASE", "OTHERWISE", "TRY", "CATCH", "RETURN", "BREAK", "CONTINUE"]
    ix = ix | FullTree.mtfind('Kind', kind);
end
ix = ix.indices;
if isempty(ix)
    k = "";
    return;
end
for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if double(nd.lineno) == ln
        k = char(nd.kind);
        return;
    end
end
k = "";
end

% -------------------------------------------------------------------------
function vars = iGetInputParams(FullTree, fStart, fnIdx)
vars = strings(0,1);
for k = 1:numel(fnIdx)
    nd = FullTree.select(fnIdx(k));
    if double(nd.lineno) == fStart
        cur = Ins(nd);
        while count(cur) > 0
            if strcmp(char(cur.kind), 'ID')
                vars(end+1) = string(cur.string); %#ok<AGROW>
            end
            try
                cur = Next(cur);
            catch
                break;
            end
        end
        return;
    end
end
end

% -------------------------------------------------------------------------
function defs = iCollectVarDefs(FullTree, eqIx, varName, fStart, fEnd)
defs = zeros(1,0);
for i = 1:numel(eqIx)
    nd = FullTree.select(eqIx(i));
    ln = double(nd.lineno);
    if ln < fStart || ln > fEnd
        continue;
    end
    lhs = Left(nd);
    if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == varName
        defs(end+1) = ln; %#ok<AGROW>
    end
end
end

% -------------------------------------------------------------------------
function tf = iVarAppearsAfter(lineMap, afterLine, fEnd, g)
% 检查从 afterLine 沿 CFG 向前（含循环回边）是否还会读到该变量。
tf = false;
if numnodes(g) == 0
    return;
end

startName = string(afterLine);
if ~any(g.Nodes.Name == startName)
    % 节点不在图中，回退到行号判断
    keys = lineMap.keys;
    for ki = 1:numel(keys)
        ln = keys{ki};
        if ln > afterLine && ln <= fEnd && lineMap(ln) > 0
            tf = true;
            return;
        end
    end
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
    ln = str2double(g.Nodes.Name(u));
    if ln ~= afterLine && ln <= fEnd && isKey(lineMap, ln) && lineMap(ln) > 0
        tf = true;
        return;
    end
    nbr = successors(g, u)';
    for v = nbr
        if ~seen(v)
            seen(v) = true;
            q(end+1) = v; %#ok<AGROW>
        end
    end
end
end

% -------------------------------------------------------------------------
function tf = iAllPathsReachTarget(g, stmts, FullTree, start, targetLine, A, B, fEnd, refMap)
% 检查从 defLine 出发的所有 CFG 路径是否最终都能到达 targetLine，
% 且途中不遇到 A 的定义或 B 的另一个定义。
persistent memo;
if isempty(memo)
    memo = dictionary;
end
key = sprintf('%d_%d_%s_%s', start, targetLine, char(A), char(B));
if isKey(memo, key)
    tf = memo(key);
    return;
end

% 收集途中禁止出现的行：A 的任何读或写，B 的另一个定义（非 defLine 的 B 写）
forbidden = iForbiddenLines(FullTree, A, B, start, targetLine, fEnd, refMap);

% 从 defLine 出发做有界 BFS，targetLine 必须在所有叶子可达集中
start = find(stmts == start, 1, 'first');
if isempty(start) || isempty(find(stmts == targetLine, 1, 'first'))
    tf = false;
    memo(key) = tf;
    return;
end

seen = false(1, numel(stmts));
q = start;
seen(start) = true;

QHead = 1;
while QHead <= numel(q)
    u = q(QHead);
    QHead = QHead + 1;
    lnU = stmts(u);

    succ = successors(g, u)';
    if isempty(succ)
        % 叶子节点：必须是 target
        if lnU ~= targetLine
            tf = false;
            memo(key) = tf;
            return;
        end
        continue;
    end

    anyProceed = false;
    for v = succ
        if any(forbidden == stmts(v))
            continue;
        end
        anyProceed = true;
        if ~seen(v)
            seen(v) = true;
            q(end+1) = v; %#ok<AGROW>
        end
    end
    if ~anyProceed && lnU ~= targetLine
        tf = false;
        memo(key) = tf;
        return;
    end
end

% 所有可达叶子都是 targetLine
tf = true;
memo(key) = tf;
end

% -------------------------------------------------------------------------
function forbidden = iForbiddenLines(FullTree, ak, B, defLine, targetLine, fEnd, refMap)
forbidden = zeros(1,0);

% A 在任何地方出现（读或写）——除了 targetLine 的 RHS
% 收集 A 的所有赋值行
eqs = FullTree.mtfind('Kind', 'EQUALS');
forbiddenA = zeros(1,0);
if count(eqs) > 0
    ix = eqs.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        ln = double(nd.lineno);
        if ln == targetLine
            continue;
        end
        lhs = Left(nd);
        if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == ak
            forbiddenA(end+1) = ln; %#ok<AGROW>
        end
    end
end
% A 的读引用行（排除 targetLine）
if isKey(refMap, char(ak))
    ak = refMap(char(ak)).keys;
    for ki = 1:numel(ak)
        ln = ak{ki};
        if ln ~= targetLine && ln > defLine && ln <= fEnd
            forbiddenA(end+1) = ln; %#ok<AGROW>
        end
    end
end
forbidden = [forbidden, unique(forbiddenA)];

% B 的另一个定义行（排除 defLine）
forbiddenB = zeros(1,0);
if count(eqs) > 0
    ix = eqs.indices;
    for i = 1:numel(ix)
        nd = FullTree.select(ix(i));
        ln = double(nd.lineno);
        if ln == defLine || ln > targetLine
            continue;
        end
        lhs = Left(nd);
        if count(lhs) == 1 && strcmp(char(lhs.kind), 'ID') && string(lhs.string) == B
            forbiddenB(end+1) = ln; %#ok<AGROW>
        end
    end
end
forbidden = unique([forbidden, forbiddenB]);
end
