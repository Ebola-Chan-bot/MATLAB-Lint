function issues = mlint_singleUseVariable(filePath)
%mlint_singleUseVariable CFG 路径枚举驱动的单次使用检测。
% 规则：
%  1. 仅当变量在下一次赋值前在所有执行路径上都零引用，才报"未使用"
%  2. 仅当全路径仅一次引用且赋值到该引用的路径无控制流分叉，才报"仅使用一次"

if nargin == 0
    issues = "禁止一次性中间变量（赋值后仅用一次/从未使用）";
    return;
end

lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ── 全局结构解析 ──
ctrlFlow = iParseControlFlow(lines, nLines);
ctrlBlocks = iCtrlBlocksFromTable(ctrlFlow);
loopBlocks = iLoopBlocksFromTable(ctrlFlow);
functionEnds = iFunctionEndsFromTable(ctrlFlow);
persistentVars = iCollectPersistent(lines, nLines);
forLoopVars     = iCollectForLoopVars(lines, nLines);
outputVars      = iCollectOutputVars(lines, nLines);
propertyVars    = iCollectProperties(lines, nLines);
assignments     = iCollectAssignments(lines, nLines);

delim = [" ", newline, ";", ",", "(", ")", "=", "+", "-", "*", "/", "~", ...
         "<", ">", "&", "|", "[", "]", "{", "}", ".", "'", ":", "%"];

% ── 为当前函数构建语句级 CFG ──
[succ, lineKinds] = iBuildStmtCFG(lines, nLines, functionEnds, loopBlocks);

% ── 按变量分组 ──
allVars = unique(string({assignments.var}));

for v = 1:numel(allVars)
    varName = allVars(v);
    if any(persistentVars == varName) || any(forLoopVars == varName) || any(propertyVars == varName)
        continue;
    end
    isOutput = any(outputVars == varName);

    % 该变量的全部赋值索引
    varAssignIdx = find(string({assignments.var}) == varName);

    for ai = 1:numel(varAssignIdx)
        a = varAssignIdx(ai);
        assignLine = assignments(a).line;
        rhs        = assignments(a).rhs;

        % 基础过滤
        if iShouldAlwaysSkip2(assignments(a).code, rhs)
            continue;
        end

        % 同变量下一次赋值
        [killLine, killIsOtherBranch] = iFindKillingAssignmentCFG(...
            assignments, a, ctrlBlocks, lines, functionEnds);

        % 输出变量末次赋值 或 分支合并模式
        if (isOutput && (killLine == 0 || killIsOtherBranch)) || killIsOtherBranch
            continue;
        end

        % 路径枚举（限制在当前函数范围内）
        funcEnd = iEnclosingFuncEnd(assignLine, functionEnds, nLines);
        result = iEnumeratePaths(lines, succ, lineKinds, ...
            assignLine, killLine, killIsOtherBranch, ...
            varName, isOutput, funcEnd, delim);

        % 循环体赋值且紧跟 continue：跨迭代引用，豁免。
        if iBlockEnd(assignLine, loopBlocks) > 0 && ~isOutput
            nextLine = iFindNextLine(lineKinds, assignLine + 1, nLines);
            if ~isempty(nextLine) && lineKinds(nextLine(1)) == "continue"
                continue;
            end
        end

        % 规则 1: 全路径零引用？
        if result.maxRefs == 0
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, assignLine, ...
                "mlint_singleUseVariable", ...
                sprintf('变量"%s"已赋值但未使用', varName)}; %#ok<AGROW>
        end

        % 规则 2: 恰好一次引用；仅当赋值到该引用之间存在“分支合并”才抑制报警
        if result.totalRefOccurrences == 1
            useLine = result.refLines(1);
            % 0 = 隐式 return 使用 / 唯一引用在 return 上 → 跳过
            if useLine == 0 || lineKinds(useLine) == "return" || ...
                    iIsLoopCarriedSingleUse(assignLine, useLine, loopBlocks, lineKinds, lines) || ...
                    iHasBranchMergeBetweenLines(assignLine, useLine, succ, lineKinds, funcEnd, killLine, killIsOtherBranch) || ...
                    (contains(iCodeOnlyLine(char(lines(useLine))), varName + "(" | varName + " (") && ...
                    endsWith(strtrim(rhs), ")" | ");"))
                continue;
            end

            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, assignLine, ...
                "mlint_singleUseVariable", ...
                sprintf('变量"%s"赋值后仅使用一次（第 %d 行），建议内联', ...
                varName, useLine)}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% ========================================================================
%  CFG 构建
% ========================================================================

function [succ, lineKinds] = iBuildStmtCFG(lines, nLines, functionEnds, loopBlocks)
% 为每条有效代码行构建后继列表和行类型。
succ = cell(nLines, 1);
lineKinds = strings(nLines, 1);

% 第一遍：标记行类型
for i = 1:nLines
    code = iCodeOnlyLine(char(lines(i)));
    if strlength(code) == 0
        continue;
    end
    if startsWith(code, "function ")
        lineKinds(i) = "function";
    elseif startsWith(code, "if ")
        lineKinds(i) = "if";
    elseif startsWith(code, "elseif ")
        lineKinds(i) = "elseif";
    elseif strcmp(code, "else")
        lineKinds(i) = "else";
    elseif startsWith(code, "for " | "while ")
        lineKinds(i) = "loop";
    elseif startsWith(code, "switch ")
        lineKinds(i) = "switch";
    elseif startsWith(code, "case ") || strcmp(code, "otherwise")
        lineKinds(i) = "case";
    elseif startsWith(code, "try")
        lineKinds(i) = "try";
    elseif startsWith(code, "catch")
        lineKinds(i) = "catch";
    elseif strcmp(code, "end")
        lineKinds(i) = "end";
    elseif strcmp(code, "break") || strcmp(code, "break;")
        lineKinds(i) = "break";
    elseif strcmp(code, "continue") || strcmp(code, "continue;")
        lineKinds(i) = "continue";
    elseif strcmp(code, "return") || strcmp(code, "return;")
        lineKinds(i) = "return";
    else
        lineKinds(i) = "stmt";
    end
end

% 修正：单行自闭合控制结构（如 if..., end）不参与嵌套匹配
for i = 1:nLines
    if ~ismember(lineKinds(i), ["if","loop","switch","try","function"])
        continue;
    end
    tokens = iExtractCtrlTokens(char(lines(i)));
    balance = 0;
    for t = 1:numel(tokens)
        tok = tokens{t};
        if ismember(tok, ["if","for","parfor","while","switch","try","function"])
            balance = balance + 1;
        elseif tok == "end"
            balance = balance - 1;
        end
    end
    if balance == 0
        lineKinds(i) = "stmt";  % 该行自闭合，不产生跨行分支
    end
end

% 第二遍：建立后继边
for i = 1:nLines
    if strlength(lineKinds(i)) == 0
        continue;
    end

    next = iFindNextLine(lineKinds, i + 1, nLines);

    switch lineKinds(i)
        case "stmt"
            succ{i} = next;
            if ~isempty(next)
                if ismember(lineKinds(next), ["elseif","else","catch","case"])
                    ownerHdr = iFindOwningBranchHeader(lineKinds, next, nLines);
                    if ownerHdr > 0
                        succ{i} = iFindNextLine(lineKinds, iFindMatchingEnd(lineKinds, ownerHdr, nLines) + 1, nLines);
                    end
                end
            end
        case {"case","catch","else"}
            % 仅由父头部可达；但从 end 回退时也应能继续
            succ{i} = iFindNextLine(lineKinds, i + 1, nLines);
        case {"if","elseif"}
            % if/elseif header → then-body 或下一个分支头/if-chain之后
            m = iFindMatchingEndOrElse(lineKinds, i, nLines);
            succ{i} = [next, iFalseBranchTarget(lineKinds, m, nLines)];
        case {"loop","switch","try"}
            m = iFindMatchingEnd(lineKinds, i, nLines);
            succ{i} = [next, iFindNextLine(lineKinds, m + 1, nLines)];
        case "end"
            % 函数尾 → 终端
            if ismember(i, functionEnds)
                succ{i} = [];
            else
                % 用 loopBlocks 精确判定是否为循环尾
                isLoopEnd = false;
                for b = 1:numel(loopBlocks.starts)
                    if loopBlocks.ends(b) == i
                        succ{i} = [loopBlocks.starts(b), iFindNextLine(lineKinds, i + 1, nLines)];
                        isLoopEnd = true;
                        break;
                    end
                end
                if ~isLoopEnd
                    succ{i} = iFindNextLine(lineKinds, i + 1, nLines);
                end
            end
        case "break"
            loopHdr = iFindEnclosingLoopHeader(lineKinds, i);
            if loopHdr > 0
                succ{i} = iFindNextLine(lineKinds, iFindMatchingEnd(lineKinds, loopHdr, nLines) + 1, nLines);
            else
                succ{i} = [];  % 死路径
            end
        case "continue"
            loopHdr = iFindEnclosingLoopHeader(lineKinds, i);
            if loopHdr > 0
                succ{i} = double(loopHdr);
            else
                succ{i} = [];
            end
        case "return"
            succ{i} = [];  % 终端
        otherwise
            succ{i} = next;
    end
end
end

function next = iFindNextLine(lineKinds, from, nLines)
for i = from:nLines
    if strlength(lineKinds(i)) > 0
        next = double(i);
        return;
    end
end
next = zeros(1, 0);
end

function m = iFindMatchingEnd(lineKinds, start, nLines)
depth = 0;
for i = start:nLines
    k = lineKinds(i);
    if strlength(k) == 0
        continue;
    end
    if ismember(k, ["if","loop","switch","try","function"])
        depth = depth + 1;
    elseif k == "end"
        depth = depth - 1;
        if depth == 0
            m = i;
            return;
        end
    end
end
m = nLines;
end

function m = iFindMatchingEndOrElse(lineKinds, start, nLines)
depth = 0;
for i = start:nLines
    k = lineKinds(i);
    if strlength(k) == 0
        continue;
    end
    if ismember(k, ["if","loop","switch","try","function"])
        if i > start
            depth = depth + 1;
        end
    elseif k == "end"
        if depth == 0
            m = i;
            return;
        end
        depth = depth - 1;
    elseif ismember(k, ["elseif","else"]) && depth == 0 && i > start
        m = i;
        return;
    end
end
m = nLines;
end

function target = iFalseBranchTarget(lineKinds, m, nLines)
% if/elseif 条件为 false 时：转到下一个分支头；若无分支则转到 if-chain 之后。
k = lineKinds(m);
if ismember(k, ["elseif","else"])
    target = double(m);
else
    target = iFindNextLine(lineKinds, m + 1, nLines);
end
end

function hdr = iFindOwningBranchHeader(lineKinds, branchLine, nLines)
% 为 elseif/else/catch/case 找到其所属头部（if/try/switch）。
hdr = 0;
if branchLine < 1 || branchLine > nLines
    return;
end
bk = lineKinds(branchLine);
if bk == "elseif" || bk == "else"
    target = "if";
elseif bk == "catch"
    target = "try";
elseif bk == "case"
    target = "switch";
else
    return;
end

depth = 0;
for i = branchLine-1:-1:1
    k = lineKinds(i);
    if strlength(k) == 0
        continue;
    end
    if k == "end"
        depth = depth + 1;
    elseif ismember(k, ["if","loop","switch","try","function"])
        if depth == 0
            if k == target
                hdr = i;
            end
            return;
        end
        depth = depth - 1;
    end
end
end

function hdr = iFindEnclosingLoopHeader(lineKinds, line)
% 从 line 往回找第一个 loop 头（最近的闭合循环）
for i = line:-1:1
    k = lineKinds(i);
    if strlength(k) == 0
        continue;
    end
    if ismember(k, ["if","loop","switch","try","function"]) && k == "loop"
        hdr = i;
        return;
    end
end
hdr = 0;
end

% ========================================================================
%  路径枚举
% ========================================================================

function result = iEnumeratePaths(lines, succ, lineKinds, ...
        startLine, killLine, killIsOtherBranch, varName, isOutput, nLines, delim)
% 节点引用预计算 + BFS：每个节点最多访问一次，不依赖路径枚举。
% 返回 minRefs/maxRefs/totalDistinctRefs 等结果。

result = struct('minRefs', 0, 'maxRefs', 0, ...
    'totalDistinctRefs', 0, 'totalRefOccurrences', 0, 'refLines', [], ...
    'pathToRefIsLinear', false, ...
    'pathWithZeroRefsIsDead', false);

if startLine > nLines
    return;
end

% 确定 effectiveEnd
stopAtKillLine = false;
if killLine > 0 && ~killIsOtherBranch
    if killLine <= startLine
        stopAtKillLine = true;
        effectiveEnd = nLines;
    else
        effectiveEnd = killLine - 1;
    end
else
    effectiveEnd = nLines;
end

if ~stopAtKillLine && startLine > effectiveEnd
    result.pathWithZeroRefsIsDead = true;
    return;
end

% ── 预计算每个节点的引用计数 ──
nodeRefCount = zeros(nLines, 1);
for i = 1:nLines
    if strlength(lineKinds(i)) == 0
        continue;
    end
    c = iCountVarRefsOnLine(lines(i), varName, delim, ...
        i == killLine && killLine > 0);
    if isOutput && lineKinds(i) == "return"
        c = c + 1;
    end
    nodeRefCount(i) = c;
end

% ── BFS 从起点探索所有可达节点 ──
visited = false(nLines, 1);
if startLine >= 1 && startLine <= nLines && ~isempty(succ{startLine})
    queue = succ{startLine};
else
    queue = iFindNextLine(lineKinds, startLine + 1, nLines);
end
queue = unique(queue(queue > 0 & queue <= nLines));
if isempty(queue)
    return;
end
visited(queue) = true;

totalRefLines = [];
totalRefOccurrences = 0;
branchingSeen = false;
head = 1;
while head <= numel(queue)
    ln = queue(head);
    head = head + 1;

    if ln > effectiveEnd
        if isOutput
            totalRefLines = union(totalRefLines, 0);
        end
        continue;
    end

    if stopAtKillLine && ln == killLine
        continue;
    end

    if nodeRefCount(ln) > 0
        totalRefLines = union(totalRefLines, ln);
        totalRefOccurrences = totalRefOccurrences + nodeRefCount(ln);
    end

    nxt = succ{ln};
    if isempty(nxt)
        continue;
    end

    if numel(nxt) > 1 || iIsBranchPoint(lineKinds, ln)
        branchingSeen = true;
    end

    for ni = 1:numel(nxt)
        to = nxt(ni);
        if to > 0 && to <= nLines && ~visited(to)
            visited(to) = true;
            queue(end+1) = to; %#ok<AGROW>
        end
    end
end

result.maxRefs = numel(totalRefLines);
result.minRefs = result.maxRefs;  % BFS 不区分路径，min=max
result.totalDistinctRefs = result.maxRefs;
result.totalRefOccurrences = totalRefOccurrences;
result.refLines = totalRefLines;
result.pathToRefIsLinear = ~branchingSeen && result.totalDistinctRefs <= 1;
result.pathWithZeroRefsIsDead = false;
end

function c = iCountVarRefsOnLine(lineText, varName, delim, isKillLine)
sj = strtrim(char(lineText));
if isempty(sj) || startsWith(sj, '%')
    c = 0;
    return;
end
code = char(MatlabLint.stripStringLiterals(sj));
if isKillLine
    eqj = iFindAssignmentEqPos(code);
    if eqj > 0
        c = sum(split(strtrim(string(code(eqj+1:end))), delim) == varName);
    else
        c = 0;
    end
else
    c = sum(split(string(code), delim) == varName);
    % 排除 LHS 同名（赋值目标不算引用）
    if c > 0
        eqj = iFindAssignmentEqPos(code);
        if eqj > 0
            lhsj = strtrim(string(code(1:eqj-1)));
            if strlength(lhsj) > 0 && lhsj == varName
                c = max(0, c - 1);
            end
        end
    end
end
end

function tf = iIsBranchPoint(lineKinds, ln)
k = lineKinds(ln);
% end 关闭非循环块时是控制流合并点（多路径汇合），也应视为"非线性"。
tf = ismember(k, ["if","elseif","loop","switch","try","function","end"]);
end

function endLine = iBlockEnd(lineNo, blocks)
endLine = 0;
if isempty(blocks.starts)
    return;
end
bestSpan = inf;
for k = 1:numel(blocks.starts)
    s = blocks.starts(k);
    e = blocks.ends(k);
    if s < lineNo && lineNo < e
        span = e - s;
        if span < bestSpan
            bestSpan = span;
            endLine = e;
        end
    end
end
end

function tf = iIsLoopCarriedSingleUse(assignLine, useLine, loopBlocks, lineKinds, lines)
tf = false;
if useLine <= 0 || useLine >= assignLine || isempty(loopBlocks.starts)
    return;
end

bestSpan = inf;
for k = 1:numel(loopBlocks.starts)
    s = loopBlocks.starts(k);
    e = loopBlocks.ends(k);
    inWhileHeader = (useLine == s) && lineKinds(s) == "loop" && startsWith(iCodeOnlyLine(char(lines(s))), "while ");
    if (inWhileHeader || (s < useLine && useLine < assignLine)) && assignLine < e
        span = e - s;
        if span < bestSpan
            bestSpan = span;
            tf = true;
        end
    end
end
end

% ========================================================================
%  辅助：kill 查找（CFG 版）
% ========================================================================

function [killLine, isOtherBranch] = iFindKillingAssignmentCFG(...
        assignments, idx, ctrlBlocks, lines, functionEnds)
killLine = 0;
isOtherBranch = false;
thisLine = assignments(idx).line;
thisVar  = assignments(idx).var;
thisFuncEnd = iEnclosingFuncEnd(thisLine, functionEnds, numel(lines));

% 赋值后若紧跟 return，则该生命周期在此终止；后续赋值不构成 kill。
if iNextExecutableIsReturn(lines, thisLine, thisFuncEnd)
    return;
end

for k = idx + 1:numel(assignments)
    if assignments(k).line > thisFuncEnd
        break;
    end
    % 非同名变量，或同名但 RHS 自引用（如 x = x + 1）都不构成杀伤
    if assignments(k).var ~= thisVar || contains(assignments(k).rhs, thisVar)
        continue;
    end
    killLine = assignments(k).line;
    isOtherBranch = iAreDifferentBranches(thisLine, killLine, ctrlBlocks, lines);
    if ~isOtherBranch && iNestingDepth(killLine, ctrlBlocks) > iNestingDepth(thisLine, ctrlBlocks)
        isOtherBranch = true;
    end
    if ~isOtherBranch
        return;
    end
end
end

function tf = iNextExecutableIsReturn(lines, lineNo, funcEnd)
tf = false;
for k = lineNo + 1:funcEnd
    code = iCodeOnlyLine(char(lines(k)));
    if strlength(code) == 0
        continue;
    end
    tf = (code == "return" || code == "return;");
    return;
end
end

function d = iNestingDepth(lineNo, blocks)
d = 0;
if isempty(blocks.starts)
    return;
end
for k = 1:numel(blocks.starts)
    if blocks.starts(k) < lineNo && lineNo < blocks.ends(k)
        d = d + 1;
    end
end
end

function tf = iAreDifferentBranches(lineA, lineB, ctrlBlocks, lines)
tf = false;
if isempty(ctrlBlocks.starts)
    return;
end
sa = ctrlBlocks.starts;
ea = ctrlBlocks.ends;
for b = 1:numel(sa)
    if sa(b) < lineA && lineA < ea(b) && sa(b) < lineB && lineB < ea(b)
        tf = iHasTopLevelElseBetween(lines, lineA, lineB);
        return;
    end
end
end

function tf = iHasTopLevelElseBetween(lines, lo, hi)
tf = false;
depth = 0;
for k = lo + 1:hi - 1
    code = iCodeOnlyLine(char(lines(k)));
    if strlength(code) == 0
        continue;
    end
    if startsWith(code, "if " | "for " | "parfor " | "while " | "switch " | "try")
        depth = depth + 1;
        continue;
    end
    if code == "end"
        if depth > 0
            depth = depth - 1;
        end
        continue;
    end
    if depth == 0 && (startsWith(code, "elseif ") || strcmp(code, "else") || ...
                      startsWith(code, "catch"))
        tf = true;
        return;
    end
end
end

% ========================================================================
%  Phase 1 — 控制流解析
% ========================================================================

function ctrlFlow = iParseControlFlow(lines, nLines)
tblBuilder = MATLAB.DataTypes.InsertiveTable();
ctrlStack  = MATLAB.Containers.Vector();
loopStack  = MATLAB.Containers.Vector();
fnStack    = MATLAB.Containers.Vector();

for i = 1:nLines
    tokens = iExtractCtrlTokens(char(lines(i)));
    for t = 1:numel(tokens)
        tok = tokens{t};
        if ismember(tok, ["function","if","for","parfor","while","switch","try"])
            ctrlStack.PushBack(i);
            if ismember(tok, ["for","parfor","while"])
                loopStack.PushBack(i);
            end
            if tok == "function"
                fnStack.PushBack(i);
            end
        elseif tok == "end"
            if ~isempty(ctrlStack.Data)
                cs = ctrlStack.Back();
                ctrlStack.PopBack();
                isLoop = ~isempty(loopStack.Data) && loopStack.Back() == cs;
                isFn   = ~isempty(fnStack.Data) && fnStack.Back() == cs;
                tblBuilder(end+1, {'ctrlStart','ctrlEnd','loopStart','loopEnd','fnEnd'}) = ...
                    {cs, i, ternary(isLoop, cs, 0), ternary(isLoop, i, 0), ternary(isFn, i, 0)};
                if isLoop
                    loopStack.PopBack();
                end
                if isFn
                    fnStack.PopBack();
                end
            end
        end
    end
end

ctrlFlow = table(tblBuilder);
end

function ctrlBlocks = iCtrlBlocksFromTable(ctrlFlow)
if isempty(ctrlFlow)
    ctrlBlocks = struct('starts', [], 'ends', []);
    return;
end
ctrlBlocks = struct('starts', double(ctrlFlow{:, 'ctrlStart'}), ...
                    'ends', double(ctrlFlow{:, 'ctrlEnd'}));
end

function loopBlocks = iLoopBlocksFromTable(ctrlFlow)
if isempty(ctrlFlow)
    loopBlocks = struct('starts', [], 'ends', []);
    return;
end
loopStarts = double(ctrlFlow{:, 'loopStart'});
loopEnds = double(ctrlFlow{:, 'loopEnd'});
loopBlocks = struct('starts', loopStarts(loopStarts > 0), ...
                    'ends', loopEnds(loopEnds > 0));
end

function functionEnds = iFunctionEndsFromTable(ctrlFlow)
if isempty(ctrlFlow)
    functionEnds = [];
    return;
end
fe = double(ctrlFlow{:, 'fnEnd'});
functionEnds = fe(fe > 0);
end

% -------------------------------------------------------------------------
function v = ternary(cond, t, f)
if cond
    v = t;
else
    v = f;
end
end

function vars = iCollectPersistent(lines, nLines)
v = MATLAB.Containers.Vector();
for i = 1:nLines
    code = iCodeOnlyLine(char(lines(i)));
    if startsWith(code, "persistent ")
        rest = strtrim(extractAfter(string(code), "persistent "));
        for token = split(rest, " ")'
            tk = strtrim(token);
            if tk ~= "" && tk ~= "..."
                v.PushBack(tk);
            end
        end
    end
end
vars = string(v.Data(:));
end

function vars = iCollectForLoopVars(lines, nLines)
v = MATLAB.Containers.Vector();
for i = 1:nLines
    code = iCodeOnlyLine(char(lines(i)));
    if startsWith(code, "for ")
        tok = extractBetween(string(code), "for ", " =");
        if ~isempty(tok) && tok ~= ""
            v.PushBack(strtrim(tok));
        end
    end
end
vars = string(v.Data(:));
end

function vars = iCollectOutputVars(lines, nLines)
v = MATLAB.Containers.Vector();
for i = 1:nLines
    code = iCodeOnlyLine(strtrim(char(lines(i))));
    if ~startsWith(code, "function ")
        continue;
    end
    rest = strtrim(extractAfter(string(code), "function "));
    if contains(rest, "=")
        lhs = strtrim(extractBefore(rest, "="));
        if lhs ~= ""
            if startsWith(lhs, "[")
                lhs = extractBetween(lhs, "[", "]");
            end
            for p = split(lhs, ",")'
                pv = strtrim(p);
                if pv ~= "" && ~startsWith(pv, "~")
                    v.PushBack(pv);
                end
            end
        end
    end
end
vars = string(v.Data(:));
end

function vars = iCollectProperties(lines, nLines)
% 收集 properties 块中定义的变量名，这些是类属性，不应被检查。
v = MATLAB.Containers.Vector();
inProps = false;
for i = 1:nLines
    code = codeLine(strtrim(char(lines(i))));
    if strlength(code) == 0
        continue;
    end
    if startsWith(lower(code), "properties")
        inProps = true;
        continue;
    end
    if inProps
        cs2 = strtrim(char(lines(i)));
        if isempty(cs2) || startsWith(cs2, '%')
            continue;
        end
        if strcmp(code, "end")
            inProps = false;
            continue;
        end
        % 简单属性名（可选默认值）：name 或 name = ...
        eqPos = strfind(code, '=');
        if isempty(eqPos)
            name = code;
        else
            name = strtrim(code(1:eqPos(1)-1));
        end
        nc = char(name);
        if ~isempty(nc) && (isstrprop(nc(1), 'alpha') || nc(1) == '_')
            v.PushBack(string(name));
        end
    end
end
vars = string(v.Data(:));
end

function assigns = iCollectAssignments(lines, nLines)
builder = MATLAB.DataTypes.ArrayBuilder();
for i = 1:nLines
    cs = strtrim(char(lines(i)));
    if isempty(cs) || startsWith(cs, '%')
        continue;
    end
    code = char(MatlabLint.stripStringLiterals(cs));
    eqPos = strfind(code, ' = ');
    if isempty(eqPos)
        continue;
    end
    eqPos = eqPos(1);
    lhs = strtrim(string(code(1:eqPos-1)));
    if strlength(lhs) == 0
        continue;
    end
    lhsMatch = extract(lhs, lettersPattern(1) + ...
        asManyOfPattern(characterListPattern('A':'Z') | ...
        characterListPattern('a':'z') | characterListPattern('0':'9') | "_", 0));
    if isempty(lhsMatch) || numel(lhsMatch) ~= 1 || strlength(lhsMatch) ~= strlength(lhs)
        continue;
    end
    builder.Append(struct('line', i, 'var', string(lhsMatch), ...
        'rhs', strtrim(string(code(eqPos+3:end))), 'code', string(code)));
end
assigns = builder.Harvest();
if isempty(assigns)
    assigns = struct('line', {}, 'var', {}, 'rhs', {}, 'code', {});
end
end

function skip = iShouldAlwaysSkip2(codeLine, rhs)
skip = false;
if startsWith(codeLine, "for ") || ...
        contains(codeLine, "==" | "~=" | ">=" | "<=") || ...
        strlength(rhs) == 0 || ...
        contains(rhs, string(extractBefore(string(codeLine), " =")))
    skip = true;
    return;
end
end

function tf = iHasBranchMergeBetweenLines(assignLine, useLine, succ, lineKinds, funcEnd, killLine, killIsOtherBranch)
% 检查 [assignLine+1, useLine] 区间内是否存在“赋值路径”和“其他路径”在同一点合并。
tf = false;
if useLine <= 0 || useLine <= assignLine
    return;
end

upper = min(useLine, funcEnd);
if killLine > 0 && ~killIsOtherBranch
    upper = min(upper, killLine - 1);
end
if upper <= assignLine
    return;
end

nLines = numel(lineKinds);
visited = false(nLines, 1);
reachableFromAssign = false(nLines, 1);

startNodes = succ{assignLine};
if isempty(startNodes)
    startNodes = iFindNextLine(lineKinds, assignLine + 1, nLines);
end
startNodes = unique(startNodes(startNodes >= assignLine + 1 & startNodes <= upper));
if isempty(startNodes)
    return;
end

queue = startNodes(:)';
visited(startNodes) = true;
reachableFromAssign(startNodes) = true;

head = 1;
while head <= numel(queue)
    from = queue(head);
    head = head + 1;

    nextNodes = succ{from};
    if isempty(nextNodes)
        continue;
    end

    for ni = 1:numel(nextNodes)
        to = nextNodes(ni);
        if to < assignLine + 1 || to > upper
            continue;
        end
        reachableFromAssign(to) = true;
        if ~visited(to)
            visited(to) = true;
            queue(end+1) = to; %#ok<AGROW>
        end
    end
end

predFromAssignPath = false(nLines, 1);
predFromOtherPath = false(nLines, 1);

for from = 1:nLines
    nextNodes = succ{from};
    if isempty(nextNodes)
        continue;
    end
    for ni = 1:numel(nextNodes)
        to = nextNodes(ni);
        if to < assignLine + 1 || to > upper
            continue;
        end
        if from == assignLine || (from >= 1 && from <= nLines && reachableFromAssign(from))
            predFromAssignPath(to) = true;
        else
            predFromOtherPath(to) = true;
        end
    end
end

for ln = assignLine + 1:upper
    if predFromAssignPath(ln) && predFromOtherPath(ln)
        tf = true;
        return;
    end
end
end

% ========================================================================
%  Utilities
% ========================================================================

function code = iCodeOnlyLine(s)
if isempty(s)
    code = "";
    return;
end
code = strtrim(string(MatlabLint.stripStringLiterals(string(s))));
p = strfind(char(code), '%');
if ~isempty(p)
    code = strtrim(extractBefore(code, p(1)));
end
end

function pos = iFindAssignmentEqPos(cs)
pos = 0;
eq = strfind(cs, '=');
for k = 1:numel(eq)
    p = eq(k);
    prev = ' ';
    next = ' ';
    if p > 1
        prev = cs(p-1);
    end
    if p < numel(cs)
        next = cs(p+1);
    end
    if prev == '=' || prev == '>' || prev == '<' || prev == '~' || next == '='
        continue;
    end
    pos = p;
    return;
end
end

function funcEnd = iEnclosingFuncEnd(lineNo, functionEnds, nLines)
% 返回包含 lineNo 的函数的结束行号。
% functionEnds 是升序排列的函数结束行向量。
funcEnd = nLines;
for k = 1:numel(functionEnds)
    if functionEnds(k) > lineNo
        funcEnd = functionEnds(k);
        return;
    end
end
end

function tokens = iExtractCtrlTokens(line)
% 从一行代码中按顺序提取所有控制流关键字（跳过字符串和注释内部）。
tokensBuilder = MATLAB.DataTypes.ArrayBuilder();
s = char(line);
n = numel(s);
inStr = false;
strCh = '';
i = 1;
while i <= n
    if inStr
        if s(i) == strCh
            if i < n && s(i+1) == strCh
                i = i + 2;
                continue;
            end
            inStr = false;
        end
        i = i + 1;
    elseif s(i) == '''' || s(i) == '"'
        inStr = true;
        strCh = s(i);
        i = i + 1;
    elseif s(i) == '%'
        break;  % 行末注释
    else
        [kw, adv] = iMatchKeyword(s, i, n);
        if adv > 0
            tokensBuilder.Append(string(kw));
            i = i + adv;
        else
            i = i + 1;
        end
    end
end

tokens = cellstr(string(tokensBuilder.Harvest()));
end

function [kw, adv] = iMatchKeyword(s, pos, n)
% 尝试在 s(pos:end) 匹配控制流关键字，返回 (keyword, 前进长度)。
kwds = ["function","if","elseif","else","for","parfor","while",...
        "switch","case","otherwise","try","catch","end",...
        "break","continue","return","spmd"];
for k = 1:numel(kwds)
    kw = kwds(k);
    L = strlength(kw);
    if pos+L-1 <= n && strcmp(s(pos:pos+L-1), kw)
        prevOK = (pos == 1 || ~isstrprop(s(pos-1), 'alphanum') && s(pos-1) ~= '_');
        nextOK = (pos+L > n || ~isstrprop(s(pos+L), 'alphanum') && s(pos+L) ~= '_');
        if prevOK && nextOK
            % 索引表达式中的 end（如 A(end+1)）不应当成控制流关键字。
            if kw == "end"
                prevNonSpace = ' ';
                for p = pos-1:-1:1
                    if ~isspace(s(p))
                        prevNonSpace = s(p);
                        break;
                    end
                end
                if ismember(prevNonSpace, ['(', '[', '{', ',', ':'])
                    continue;
                end
            end
            adv = L;
            return;
        end
    end
end
kw = "";
adv = 0;
end



