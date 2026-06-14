function issues = mlint_noStaticPrivateMethod(filePath)
%mlint_noStaticPrivateMethod 禁止 Static private 方法，应改为 classdef 之后的局部函数。

if nargin == 0
    issues = "禁止 Static private 方法，应改为写在 classdef 块之后的局部函数（可直接用函数名调用）";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

inClass = false;
for i = 1:numel(lines)
    s = strtrim(char(lines(i)));
    if isempty(s)
        continue;
    end
    if startsWith(lower(s), "classdef")
        inClass = true;
        continue;
    end
    if inClass && contains(lower(s), "methods") && contains(lower(s), "static") ...
              && contains(lower(s), "private")
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noStaticPrivateMethod", ...
            sprintf('Static private 方法应改为 classdef 之后的局部函数：%s', strtrim(s))}; %#ok<AGROW>
    end
    if inClass && contains(lower(s), "end")
        inClass = false;
    end
end

issues = table(issuesBuilder);
end
