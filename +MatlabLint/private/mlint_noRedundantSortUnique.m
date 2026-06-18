function issues = mlint_noRedundantSortUnique(filePath)
%mlint_noRedundantSortUnique 禁止 sort(unique(...)) 冗余写法。

if nargin == 0
    issues = "禁止 sort(unique(...)) 冗余写法";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    s = strtrim(char(AllLines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    if contains(codeLine(s), "sort(unique(" | "sort (unique(" | "sort( unique(" | "sort ( unique(")
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noRedundantSortUnique", ...
            sprintf('冗余写法 sort(unique(...))："%s"，unique 默认已排序', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end



