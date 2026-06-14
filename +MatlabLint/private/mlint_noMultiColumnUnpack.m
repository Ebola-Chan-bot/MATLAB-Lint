function issues = mlint_noMultiColumnUnpack(filePath)
%mlint_noMultiColumnUnpack 不应把表的多个列拆为多个返回值，应直接返回 table。

if nargin == 0
    issues = "不应将表的多个列拆分为多个返回值（如 values=tbl.value; bodies=tbl.body;），应直接返回 table";
    return;
end
lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% 先收集所有 table() / InsertiveTable 变量
tblVars = iCollectTableVars(lines, nLines);
if isempty(tblVars)
    issues = table(issuesBuilder);
    return;
end

% 对每个表变量，检测紧跟的列拆分模式
for tv = 1:numel(tblVars)
    vn = tblVars(tv);
    unpackLines = iFindColumnUnpacks(lines, nLines, vn);
    if numel(unpackLines) >= 2
        isRow = makeIssue(filePath, unpackLines(1), ...
            "mlint_noMultiColumnUnpack", ...
            sprintf('不应将表 "%s" 的多个列拆分为独立变量，建议直接返回 table', vn));
        issuesBuilder(end+1, {'file','line','rule','message'}) = ...
            {isRow.file, isRow.line, isRow.rule, isRow.message};
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function tblVars = iCollectTableVars(lines, nLines)
varBuilder = MATLAB.DataTypes.ArrayBuilder();

for i = 1:nLines
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

    % 匹配: varName = table(builder);  或  varName = table(fields...);
    eqPos = strfind(code, '=');
    if isempty(eqPos)
        continue;
    end
    lhs = strtrim(code(1:eqPos(1)-1));
    rhs = strtrim(code(eqPos(1)+1:end));
    if isempty(lhs) || ~isstrprop(lhs(1), 'alpha')
        continue;
    end
    s = strrep(rhs, ' ', '');
    if startsWith(s, "table(") || startsWith(s, "MATLAB.DataTypes.InsertiveTable(")
        varBuilder.Append(string(lhs));
    end
end

tblVars = string(varBuilder.Harvest());
tblVars = unique(tblVars);
end

% -------------------------------------------------------------------------
function unpackLines = iFindColumnUnpacks(allLines, nLines, tblVar)
lineBuilder = MATLAB.Containers.Vector();
vn = string(tblVar);

for i = 1:nLines
    raw = strtrim(char(allLines(i)));
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

    % 匹配: something = tbl.columnName  或  something = string(tbl.columnName)
    eqPos = strfind(code, '=');
    if isempty(eqPos)
        continue;
    end
    rhs = strtrim(code(eqPos(1)+1:end));
    rhsNoSp = strrep(rhs, ' ', '');

    % 允许 rhs 为 string(tableVar.xxx) 或 tableVar.xxx
    if contains(rhsNoSp, vn + '.')
        lineBuilder.PushBack(i);
    end
end
unpackLines = double(lineBuilder.Data(:));
end
