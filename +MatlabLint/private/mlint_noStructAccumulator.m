function issues = mlint_noStructAccumulator(filePath)
%mlint_noStructAccumulator struct 累积器应改用 InsertiveTable（每个 struct 字段对应一列）。

if nargin == 0
    issues = "禁止 struct 数组累积（end+1/cat 追加 struct），应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）";
    return;
end
lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = iSplitFunctions(lines, nLines);

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
            issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, firstAppend, ...
                "mlint_noStructAccumulator", ...
                sprintf('变量 "%s" 为 struct 数组累积器，应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）', ...
                vn))); %#ok<AGROW>
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
function accVars = iCollectStructAccumulators(lines, fnStart, fnEnd)
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
pat = lettersPattern(1) + asManyOfPattern(characterListPattern('A':'Z') | ...
    characterListPattern('a':'z') | characterListPattern('0':'9') | "_", 0);
idx = extract(lhs, pat);
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
    code = char(MatlabLint.stripStringLiterals(raw));
    cp = strfind(code, '%');
    if ~isempty(cp)
        code = strtrim(code(1:cp(1)-1));
    else
        code = strtrim(code);
    end
    vn = iExtractStructAppendVar(code);
    if strlength(vn) > 0 && string(vn) == string(varName)
        firstLine = i;
        return;
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



