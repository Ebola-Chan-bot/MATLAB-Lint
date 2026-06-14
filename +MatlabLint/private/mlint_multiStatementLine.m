function issues = mlint_multiStatementLine(filePath)
%mlint_multiStatementLine 禁止用分号将多行代码压成一行。

if nargin == 0
    issues = "禁止用分号将多行代码压成一行";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    clean = char(MatlabLint.stripStringLiterals(s));
    commentPos = strfind(clean, '%');
    if ~isempty(commentPos)
        clean = clean(1:commentPos(1)-1);
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
        issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_multiStatementLine", ...
            sprintf('一行包含多条语句："%s"', s))); %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end



