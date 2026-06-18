function issues = mlint_multiStatementLine(filePath)
%mlint_multiStatementLine 禁止用分号将多行代码压成一行。

if nargin == 0
    issues = "禁止用分号将多行代码压成一行";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    s = strtrim(char(AllLines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    clean = codeLine(s);
    if isempty(clean)
        continue;
    end
    depth = 0;
    semiCount = 0;
    for ch = clean
        if any(ch == '({[')
            depth = depth + 1;
        elseif any(ch == ')}]')
            depth = depth - 1;
        elseif ch == ';' && depth == 0
            semiCount = semiCount + 1;
        end
    end
    minSemi = 2;
    if startsWith(strtrim(clean), "for " | "while " | "if ")
        minSemi = 1;
    end
    if semiCount >= minSemi
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_multiStatementLine", ...
            sprintf('一行包含多条语句："%s"', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end



