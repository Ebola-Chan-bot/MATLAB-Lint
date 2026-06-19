function issues = mlint_noBuiltin(filePath)
%mlint_noBuiltin 禁止 builtin(...) 调用。

if nargin == 0
    issues = "禁止 builtin(...) 调用";
    return;
end
AllLines = splitlines(fileread( filePath ));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    % 不转 string 标量会在此处对应的输出构造链路复现真实错误：
    % mlint_noBuiltin:19, sprintf 不支持 cell 输入。
    s = strtrim(AllLines( i ));
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



