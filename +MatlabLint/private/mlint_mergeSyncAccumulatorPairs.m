function issues = mlint_mergeSyncAccumulatorPairs(filePath)
%mlint_mergeSyncAccumulatorPairs 同步累积的 ArrayBuilder/Vector 对应合并为 InsertiveTable。

if nargin == 0
    issues = "同步追加和收割的多个 ArrayBuilder/Vector 应合并为 MATLAB.DataTypes.InsertiveTable";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = splitFunctions(AllLines, numel(AllLines));

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd   = funcs(f).end;
    varBuilder = MATLAB.DataTypes.ArrayBuilder();
    for i = fnStart:fnEnd
        raw = strtrim(char(AllLines(i)));
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
    vars = unique(string(varBuilder.Harvest()));
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
        appendRowsBuilder = MATLAB.Containers.Vector();
        varName = vars(vi);
        for scanLine = fnStart:fnEnd
            raw = strtrim(char(AllLines(scanLine)));
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
                appendCounts(vi) = appendCounts(vi) + 1;
                appendRowsBuilder.PushBack(scanLine);
                if firstAppendLines(vi) == 0
                    firstAppendLines(vi) = scanLine;
                end
                if hasAppend && ~hasPushBack
                    appendKinds(vi) = iPickKind(appendKinds(vi), "Append");
                elseif hasPushBack && ~hasAppend
                    appendKinds(vi) = iPickKind(appendKinds(vi), "PushBack");
                else
                    appendKinds(vi) = iPickKind(appendKinds(vi), "Mixed");
                end
            end

            hasHarvest = contains(code, varName + ".Harvest()");
            hasData = contains(code, varName + ".Data");
            if hasHarvest || hasData
                harvestLines(vi) = scanLine;
                if hasHarvest && ~hasData
                    harvestKinds(vi) = iPickKind(harvestKinds(vi), "Harvest");
                elseif hasData && ~hasHarvest
                    harvestKinds(vi) = iPickKind(harvestKinds(vi), "Data");
                else
                    harvestKinds(vi) = iPickKind(harvestKinds(vi), "Mixed");
                end
            end
        end
        appendLines{vi} = double(appendRowsBuilder.Data(:));
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




