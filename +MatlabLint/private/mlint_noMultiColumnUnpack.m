function issues = mlint_noMultiColumnUnpack(filePath)
%mlint_noMultiColumnUnpack 不应把表的多个列拆为多个返回值，应直接返回 table。

if nargin == 0
    issues = "不应将表的多个列拆分为多个返回值（如 values=tbl.value; bodies=tbl.body;），应直接返回 table，并要求上游调用方改为按 table 使用";
    return;
end
lines = splitlines(string(fileread(filePath)));
nLines = numel(lines);

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% 先拦截 table2array 拆表（无论出现次数，均视为违规）
    lineBuilder = MATLAB.Containers.Vector();
    for i = 1:nLines
        raw = strtrim(char(lines(i)));
        if isempty(raw) || raw(1) == '%'
            continue;
        end
        code = codeLine(raw);
        if isempty(code)
            continue;
        end
        if contains(strrep(code, ' ', ''), "table2array(")
            lineBuilder.PushBack(i);
        end
    end
    t2aLines = unique(double(lineBuilder.Data(:)));
for ti = 1:numel(t2aLines)
    issuesBuilder(end+1, {'file','line','rule','message'}) = ...
        {filePath, t2aLines(ti), "mlint_noMultiColumnUnpack", ...
        "禁止通过 table2array 拆表；必须直接返回 table，并要求上游调用方调整为按 table 使用"}; %#ok<AGROW>
end

% 先收集所有 table() / InsertiveTable 变量
    varBuilder = MATLAB.DataTypes.ArrayBuilder();
    
    for i = 1:nLines
        raw = strtrim(char(lines(i)));
        if isempty(raw) || raw(1) == '%'
            continue;
        end
        code = codeLine(raw);
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
        if startsWith(s, "table(" | "MATLAB.DataTypes.InsertiveTable(")
            varBuilder.Append(string(lhs));
        end
    end
    
    tblVars = string(varBuilder.Harvest());
    tblVars = unique(tblVars);
if isempty(tblVars)
    issues = table(issuesBuilder);
    return;
end

% 对每个表变量，检测紧跟的列拆分模式
for tv = 1:numel(tblVars)
    allLines = lines;
    lineBuilder = MATLAB.Containers.Vector();
    vn = string(tblVars(tv));
    
    for i = 1:nLines
        raw = strtrim(char(allLines(i)));
        if isempty(raw) || raw(1) == '%'
            continue;
        end
        code = codeLine(raw);
        if isempty(code)
            continue;
        end
    
        % 匹配: something = tbl.columnName  或  something = string(tbl.columnName)
        eqPos = strfind(code, '=');
        if isempty(eqPos)
            continue;
        end
    
        % 允许 rhs 为 string(tableVar.xxx) 或 tableVar.xxx
        if contains(strrep(strtrim(code(eqPos(1)+1:end)), ' ', ''), vn + '.')
            lineBuilder.PushBack(i);
        end
    end
    unpackLines = double(lineBuilder.Data(:));
    if numel(unpackLines) >= 2
        issuesBuilder(end+1, {'file','line','rule','message'}) = ...
            {filePath, unpackLines(1), "mlint_noMultiColumnUnpack", ...
            sprintf('不应将表 "%s" 的多个列拆分为独立变量；必须直接返回 table，并要求上游调用方调整为按 table 使用', vn)};
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------

% -------------------------------------------------------------------------

% -------------------------------------------------------------------------



