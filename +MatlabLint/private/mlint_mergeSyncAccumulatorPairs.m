function issues = mlint_mergeSyncAccumulatorPairs(filePath)
%mlint_mergeSyncAccumulatorPairs 同步累积的 ArrayBuilder/Vector 对应合并为 InsertiveTable。

if nargin == 0
    issues = "同步追加和收割的多个 ArrayBuilder/Vector 应合并为 MATLAB.DataTypes.InsertiveTable";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = splitFunctions(lines, numel(lines));

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd   = funcs(f).end;
    vars = iCollectAccumulatorVars(lines, fnStart, fnEnd);
    if numel(vars) < 2
        continue;
    end

    % 计算每个变量在该函数内的追加/收割特征
    appendCounts = zeros(numel(vars), 1);
    harvestLines = zeros(numel(vars), 1);
    firstAppendLines = zeros(numel(vars), 1);
    appendLines = cell(numel(vars), 1);
    appendKinds = strings(numel(vars), 1);
    harvestKinds = strings(numel(vars), 1);
    for vi = 1:numel(vars)
        [appendCounts(vi), harvestLines(vi), firstAppendLines(vi), appendLines{vi}, appendKinds(vi), harvestKinds(vi)] = ...
            iCollectAccumulatorOps(lines, fnStart, fnEnd, vars(vi));
    end

    % 查找“真正同步”的配对：同构造器、同追加方式、追加次数>=2、逐次追加邻近、同收割方式且收割邻近
    for vi = 1:numel(vars)-1
        for vj = vi+1:numel(vars)
            if iIsSynchronousPair(appendCounts(vi), harvestLines(vi), appendLines{vi}, appendKinds(vi), harvestKinds(vi), ...
                    appendCounts(vj), harvestLines(vj), appendLines{vj}, appendKinds(vj), harvestKinds(vj))
                issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, min(firstAppendLines(vi), firstAppendLines(vj)), ...
                    "mlint_mergeSyncAccumulatorPairs", ...
                    sprintf('变量 "%s" 和 "%s" 始终同步累积和收割（各 %d 次追加），应合并为单个 MATLAB.DataTypes.InsertiveTable', ...
                    vars(vi), vars(vj), appendCounts(vi))}; %#ok<AGROW>
            end
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function vars = iCollectAccumulatorVars(lines, fnStart, fnEnd)
varBuilder = MATLAB.DataTypes.ArrayBuilder();
for i = fnStart:fnEnd
    raw = strtrim(char(lines(i)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    code = codeLine(raw);
    if isempty(code)
        continue;
    end
    % 匹配 varName = MATLAB.DataTypes.ArrayBuilder(); 或 Vector()
    eqPos = strfind(code, '=');
    if isempty(eqPos)
        continue;
    end
    lhs = strtrim(code(1:eqPos(1)-1));
    rhs = strtrim(code(eqPos(1)+1:end));
    if isempty(lhs) || ~isstrprop(lhs(1), 'alpha')
        continue;
    end
    if startsWith(rhs, "MATLAB.DataTypes.ArrayBuilder(" | "MATLAB.Containers.Vector(")
        varBuilder.Append(string(lhs));
    end
end
vars = string(varBuilder.Harvest());
vars = unique(vars);
end

% -------------------------------------------------------------------------
function [appendCount, harvestLine, firstAppendLine, appendRows, appendKind, harvestKind] = iCollectAccumulatorOps(lines, fnStart, fnEnd, varName)
appendCount = 0;
harvestLine = 0;
firstAppendLine = 0;
appendRowsBuilder = MATLAB.Containers.Vector();
appendKind = "";
harvestKind = "";

for i = fnStart:fnEnd
    raw = strtrim(char(lines(i)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    code = string(codeLine(raw));
    if strlength(code) == 0
        continue;
    end

    hasAppend = contains(code, varName + ".Append(");
    hasPushBack = contains(code, varName + ".PushBack(");
    if hasAppend || hasPushBack
        appendCount = appendCount + 1;
        appendRowsBuilder.PushBack(i);
        if firstAppendLine == 0
            firstAppendLine = i;
        end
        if hasAppend && ~hasPushBack
            appendKind = iPickKind(appendKind, "Append");
        elseif hasPushBack && ~hasAppend
            appendKind = iPickKind(appendKind, "PushBack");
        else
            appendKind = iPickKind(appendKind, "Mixed");
        end
    end

    hasHarvest = contains(code, varName + ".Harvest()");
    hasData = contains(code, varName + ".Data");
    if hasHarvest || hasData
        harvestLine = i;
        if hasHarvest && ~hasData
            harvestKind = iPickKind(harvestKind, "Harvest");
        elseif hasData && ~hasHarvest
            harvestKind = iPickKind(harvestKind, "Data");
        else
            harvestKind = iPickKind(harvestKind, "Mixed");
        end
    end
end
appendRows = double(appendRowsBuilder.Data(:));
end

function tf = iIsSynchronousPair(aCount, aHarvestLine, aAppendRows, aAppendKind, aHarvestKind, ...
        bCount, bHarvestLine, bAppendRows, bAppendKind, bHarvestKind)
tf = false;

if aCount >= 2 && aCount == bCount && ...
        aHarvestLine > 0 && bHarvestLine > 0 && abs(aHarvestLine - bHarvestLine) <= 3 && ...
        strlength(aAppendKind) > 0 && strlength(bAppendKind) > 0 && aAppendKind == bAppendKind && ...
        strlength(aHarvestKind) > 0 && strlength(bHarvestKind) > 0 && aHarvestKind == bHarvestKind && ...
        numel(aAppendRows) == numel(bAppendRows) && ...
        ~any(abs(aAppendRows - bAppendRows) > 3)
    tf = true;
    return;
end
end

function out = iPickKind(curr, next)
if strlength(curr) == 0
    out = next;
elseif curr == next
    out = curr;
else
    out = "Mixed";
end
end



