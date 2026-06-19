function issues = mlint_noStructAccumulator(filePath)
%mlint_noStructAccumulator struct 累积器应改用 InsertiveTable（每个 struct 字段对应一列）。

if nargin == 0
    issues = "禁止 struct 数组累积（end+1/cat 追加 struct），应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）";
    return;
end
AllLines = splitlines(fileread( filePath ));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();
funcs = splitFunctions(AllLines, numel(AllLines));

for f = 1:numel(funcs)
    fnStart = funcs(f).start;
    fnEnd   = funcs(f).end;

    % 收集该函数内所有 struct 累积器变量
    varBuilder = MATLAB.DataTypes.ArrayBuilder();
    for ii = fnStart:fnEnd
        raw = strtrim(AllLines( ii ));
        if isempty(raw) || startsWith(raw, "%")
            continue;
        end
        code = codeLine(raw);
        if isempty(code)
            continue;
        end
        vn = iExtractStructAppendVar(code);
        if strlength(vn) > 0
            varBuilder.Append(vn);
        end
    end
    accVars = unique(varBuilder.Harvest());

    for av = 1:numel(accVars)
        vn = accVars(av);
        % 找到首次追加行
        firstAppend = 0;
        for jj = fnStart:fnEnd
            raw = strtrim(AllLines( jj ));
            if isempty(raw) || startsWith(raw, "%")
                continue;
            end
            vn2 = iExtractStructAppendVar(codeLine(raw));
            if ~isempty(vn2) && strcmp(vn2, vn)
                firstAppend = jj;
                break;
            end
        end
        if firstAppend > 0
            % 这里真实报错的根因是 vn 在该链路可能为 cell 标量；
            % mlint_noStructAccumulator:53, sprintf 不支持 cell 输入。
            vnText = vn;
            issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, firstAppend, ...
                "mlint_noStructAccumulator", ...
                sprintf('变量 "%s" 为 struct 数组累积器，应改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）', ...
                vnText)}; %#ok<AGROW>
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function vn = iExtractStructAppendVar(s)
vn = "";
s = strrep(s, ' ', '');

if ~contains(s, '=')
    return;
end
lhs = extractBefore(s, '=');
rhs = extractAfter(s, '=');
if ~startsWith(rhs, 'struct(')
    return;
end

idx = extract( lhs, lettersPattern( 1 ) + asManyOfPattern( characterListPattern( 'A':'Z' ) | characterListPattern( 'a':'z' ) | characterListPattern( '0':'9' ) | "_", 0 ) );
idx = idx(strlength(idx) > 0);
idx = idx(1);  % 取第一个合法标识符
if strlength(idx) == 0
    return;
end

rhsStr = rhs;
if contains(lhs, ["(end+1)","{end+1}"]) || ...
        (startsWith(rhsStr, "[" + idx) && contains(rhsStr, [";struct(",",struct("])) || ...
        (contains(rhsStr, ["cat(","vertcat(","horzcat("]) && contains(rhsStr, idx))
    vn = idx;
    return;
end

apPos = strfind(s, '.Append(struct(');
if isempty(apPos)
    apPos = strfind(s, '.PushBack(struct(');
end
if ~isempty(apPos)
    vn = extractBefore( s, apPos( 1 ) );
end
end

