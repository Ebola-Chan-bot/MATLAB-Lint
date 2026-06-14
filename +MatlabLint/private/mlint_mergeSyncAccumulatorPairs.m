function issues = mlint_mergeSyncAccumulatorPairs(filePath)
%mlint_mergeSyncAccumulatorPairs 同步累积的 ArrayBuilder/Vector 对应合并为 InsertiveTable。

if nargin == 0
    issues = "同步追加和收割的多个 ArrayBuilder/Vector 应合并为 MATLAB.DataTypes.InsertiveTable";
    return;
end
lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = iSplitFunctions(lines, nLines);

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd   = funcs(f).end;
    vars = iCollectAccumulatorVars(lines, fnStart, fnEnd);
    if numel(vars) < 2
        continue;
    end

    % 计算每个变量在该函数内的 Append/PushBack 次数和 Harvest/Data 行
    counts = zeros(numel(vars), 2);  % [appendCount, harvestLine]
    for vi = 1:numel(vars)
        [appendCount, harvestLine] = iCountAccumulatorOps(lines, fnStart, fnEnd, vars(vi));
        counts(vi, 1) = appendCount;
        counts(vi, 2) = harvestLine;
    end

    % 查找 appendCount 相同且 harvest 行相邻的配对
    for vi = 1:numel(vars)-1
        for vj = vi+1:numel(vars)
            if counts(vi,1) > 0 && counts(vi,1) == counts(vj,1) && ...
                    counts(vi,2) > 0 && counts(vj,2) > 0 && ...
                    abs(counts(vi,2) - counts(vj,2)) <= 3
                issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, fnStart, ...
                    "mlint_mergeSyncAccumulatorPairs", ...
                    sprintf('变量 "%s" 和 "%s" 始终同步累积和收割（各 %d 次追加），应合并为单个 MATLAB.DataTypes.InsertiveTable', ...
                    vars(vi), vars(vj), counts(vi,1)))); %#ok<AGROW>
            end
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function funcs = iSplitFunctions(lines, nLines)
funcsBuilder = MATLAB.DataTypes.ArrayBuilder();
depth = 0;
fnStart = 0;
for i = 1:nLines
    kw = iLeadingKeyword(char(lines(i)));
    if kw == "function" && depth == 0
        fnStart = i;
    end
    if ismember(kw, ["if","for","parfor","while","switch","try","function"])
        depth = depth + 1;
    elseif kw == "end"
        depth = depth - 1;
        if depth == 0 && fnStart > 0
            funcsBuilder.Append(struct('start', fnStart, 'end', i));
            fnStart = 0;
        end
    end
end
funcs = funcsBuilder.Harvest();
if isempty(funcs)
    funcs = struct('start', {}, 'end', {});
end
end

% -------------------------------------------------------------------------
function vars = iCollectAccumulatorVars(lines, fnStart, fnEnd)
varBuilder = MATLAB.DataTypes.ArrayBuilder();
for i = fnStart:fnEnd
    raw = strtrim(char(lines(i)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    code = char(MatlabLint.stripStringLiterals(raw));
    cp = strfind(code, '%');
    if ~isempty(cp)
        code = strtrim(code(1:cp(1)-1));
    else
        code = strtrim(code);
    end
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
    if startsWith(rhs, "MATLAB.DataTypes.ArrayBuilder(" | "MATLAB.DataTypes.Vector(")
        varBuilder.Append(string(lhs));
    end
end
vars = string(varBuilder.Harvest());
vars = unique(vars);
end

% -------------------------------------------------------------------------
function [appendCount, harvestLine] = iCountAccumulatorOps(lines, fnStart, fnEnd, varName)
appendCount = 0;
harvestLine = 0;

for i = fnStart:fnEnd
    raw = strtrim(char(lines(i)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    code = char(MatlabLint.stripStringLiterals(raw));
    cp = strfind(code, '%');
    if ~isempty(cp)
        code = strtrim(code(1:cp(1)-1));
    else
        code = strtrim(code);
    end
    % 统计 .Append( 或 .PushBack( 调用次数
    appendCount = appendCount + numel(strfind(code, [char(varName) '.Append(']));
    appendCount = appendCount + numel(strfind(code, [char(varName) '.PushBack(']));
    % 收割行
    if contains(code, varName + ".Harvest()" | varName + ".Data")
        harvestLine = i;
    end
end
end

% -------------------------------------------------------------------------
function kw = iLeadingKeyword(line)
s = strtrim(char(line));
if isempty(s) || s(1) == '%'
    kw = "";
    return;
end
kwds = ["function","if","for","parfor","while","switch","try","end"];
for ki = 1:numel(kwds)
    k = kwds(ki);
    L = strlength(k);
    if strlength(s) >= L && strcmp(s(1:L), k) && ...
            (strlength(s) == L || ~isstrprop(s(L+1), 'alphanum') && s(L+1) ~= '_')
        kw = k;
        return;
    end
end
kw = "";
end



