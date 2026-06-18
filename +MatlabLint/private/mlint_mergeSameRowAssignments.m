function issues = mlint_mergeSameRowAssignments(filePath)
%mlint_mergeSameRowAssignments 同一行多列赋值应合并为单行。

if nargin == 0
    issues = "同一行多列赋值应合并为单行写法";
    return;
end

AllLines = splitlines(string(fileread(filePath)));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

nLines = numel(AllLines);
i = 1;
while i <= nLines
    s = strtrim(char(AllLines(i)));
    if isempty(s) || startsWith(s, '%')
        i = i + 1;
        continue;
    end

    [ok, varName, rowToken] = iParseCellRowAssign(s);
    if ~ok || rowToken ~= "end+1"
        i = i + 1;
        continue;
    end

    j = i + 1;
    mergeCount = 1;
    while j <= nLines
        sj = strtrim(char(AllLines(j)));
        if isempty(sj) || startsWith(sj, '%')
            j = j + 1;
            continue;
        end

        [ok2, varName2, rowToken2] = iParseCellRowAssign(sj);
        if ~ok2 || varName2 ~= varName || rowToken2 ~= "end"
            break;
        end

        mergeCount = mergeCount + 1;
        j = j + 1;
    end

    if mergeCount >= 2
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_mergeSameRowAssignments", ...
            sprintf('检测到同一行多列分散赋值（第 %d-%d 行），建议合并为单行：%s(end+1, ["col1", "col2", ...]) = {v1, v2, ...};', ...
            i, j - 1, char(varName))}; %#ok<AGROW>
        i = j;
        continue;
    end

    i = i + 1;
end

issues = table(issuesBuilder);
end

function [ok, varName, rowToken] = iParseCellRowAssign(s)
ok = false;
varName = "";
rowToken = "";

s = strrep(strrep(s, ' ', ''), sprintf('\t'), '');
bracePos = strfind(s, '{');
if isempty(bracePos) || bracePos(1) < 2
    return;
end

lhsVar = string(s(1:bracePos(1)-1));
if ~isValidIdentifier(lhsVar)
    return;
end

parts = strfind(s, '}=');
if isempty(parts)
    return;
end
parts = split(string(s(bracePos(1)+1:parts(1)-1)), ',');
if numel(parts) < 2
    return;
end

switch strtrim(parts(1))
    case "end+1", rowToken = "end+1";
    case "end",   rowToken = "end";
    otherwise, return;
end

if ~((startsWith(strtrim(parts(2)), '"') && endsWith(strtrim(parts(2)), '"')) || ...
     (startsWith(strtrim(parts(2)), "'") && endsWith(strtrim(parts(2)), "'")))
    return;
end

ok = true;
varName = lhsVar;
end



