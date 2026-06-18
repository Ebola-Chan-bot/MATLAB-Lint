function issues = mlint_noBuiltin(filePath)
%mlint_noBuiltin 禁止 builtin(...) 调用。

if nargin == 0
    issues = "禁止 builtin(...) 调用";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    s = strtrim(char(AllLines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    if contains(s, "builtin(")
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noBuiltin", ...
            sprintf('避免使用 builtin(...)，请直接调用目标函数：%s', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end



