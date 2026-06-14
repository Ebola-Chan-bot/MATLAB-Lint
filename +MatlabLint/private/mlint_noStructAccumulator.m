function issues = mlint_noStructAccumulator(filePath)
%mlint_noStructAccumulator struct 累积器应改用 InsertiveTable（每个 struct 字段对应一列）。

if nargin == 0
    issues = "禁止 struct 数组累积（end+1/cat 追加 struct），应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = splitFunctions(lines, numel(lines));

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd   = funcs(f).end;

    % 收集该函数内所有 struct 累积器变量
    accVars = iCollectStructAccumulators(lines, fnStart, fnEnd);
    for av = 1:numel(accVars)
        vn = accVars(av);
        % 找到首次追加行作为报告位置
        firstAppend = iFindFirstStructAppend(lines, fnStart, fnEnd, vn);
        if firstAppend > 0
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, firstAppend, ...
                "mlint_noStructAccumulator", ...
                sprintf('变量 "%s" 为 struct 数组累积器，应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）', ...
                vn)}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function accVars = iCollectStructAccumulators(lines, fnStart, fnEnd)
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

    % 检测 struct 累积追加模式：
    %   var(end+1) = struct(...)
    %   var = [var; struct(...)] 或 var = [var, struct(...)]
    vn = iExtractStructAppendVar(code);
    if strlength(vn) > 0
        varBuilder.Append(vn);
    end
end

accVars = string(varBuilder.Harvest());
accVars = unique(accVars);
end

% -------------------------------------------------------------------------
function vn = iExtractStructAppendVar(code)
vn = "";
s = strrep(code, ' ', '');  % 去空格简化匹配

% 模式: varName(end+1)=struct(  或  varName{end+1}=struct(
eqPos = strfind(s, '=');
if isempty(eqPos)
    return;
end
lhs = s(1:eqPos(1)-1);
rhs = s(eqPos(1)+1:end);
if ~startsWith(rhs, 'struct(')
    return;
end
% 提取变量名（去索引后缀）
idx = extract(lhs, lettersPattern(1) + asManyOfPattern(characterListPattern('A':'Z') | ...
    characterListPattern('a':'z') | characterListPattern('0':'9') | "_", 0));
if strlength(idx) == 0
    return;
end
rhsStr = string(rhs);
% lhs 含 end+1 索引 → 直接命中
% 或 rhs 形如 [idx;struct( / [idx,struct(
% 或 rhs 含 cat/vertcat/horzcat 且引用了 idx
if contains(lhs, ["(end+1)","{end+1}"]) || ...
        (startsWith(rhsStr, "[" + idx) && contains(rhsStr, [";struct(",",struct("])) || ...
        (contains(rhsStr, ["cat(","vertcat(","horzcat("]) && contains(rhsStr, idx))
    vn = string(idx);
    return;
end

% 模式: varName.Append(struct(...)) 或 varName.PushBack(struct(...))  (ArrayBuilder/Vector)
apPos = strfind(s, '.Append(struct(');
if isempty(apPos)
    apPos = strfind(s, '.PushBack(struct(');
end
if ~isempty(apPos)
    vn = string(extractBefore(s, apPos(1)));
    return;
end
end

% -------------------------------------------------------------------------
function firstLine = iFindFirstStructAppend(lines, fnStart, fnEnd, varName)
firstLine = 0;
for i = fnStart:fnEnd
    raw = strtrim(char(lines(i)));
    if isempty(raw) || raw(1) == '%'
        continue;
    end
    code = codeLine(raw);
    vn = iExtractStructAppendVar(code);
    if strlength(vn) > 0 && string(vn) == string(varName)
        firstLine = i;
        return;
    end
end
end



