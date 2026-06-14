function issues = mlint_noStructArray(filePath)
%mlint_noStructArray 禁止 struct 数组 — 建议改用 table。

if nargin == 0
    issues = "禁止 struct 数组，建议改用 table";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    s = strtrim(char(lines(i)));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    cs = codeLine(s);

    if contains(cs, "repmat") && contains(cs, "struct(")
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noStructArray", ...
            sprintf('发现 struct 数组写法（repmat+struct）："%s"，建议改用 table', s)}; %#ok<AGROW>
    end
    if contains(cs, "end+1) = struct(" | "end + 1) = struct(")
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noStructArray", ...
            sprintf('struct 数组动态扩容："%s"，建议用 table 收集结果', s)}; %#ok<AGROW>
    end
    if contains(cs, "[") && contains(cs, ".") && contains(cs, "]")
        tok = extractBetween(string(cs), "[", "]");
        if ~isempty(tok)
            idPat = lettersPattern(1) + asManyOfPattern(characterListPattern('A':'Z') | characterListPattern('a':'z') | characterListPattern('0':'9') | "_", 0);
            if any(contains(tok, idPat + "." + idPat)) && ...
               ~any(contains(tok, idPat + "(")) && ...
               ~any(contains(tok, characterListPattern('A':'Z') + asManyOfPattern(characterListPattern('A':'Z') | characterListPattern('a':'z') | characterListPattern('0':'9') | "_", 0) + "." + idPat))
                issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noStructArray", ...
                    sprintf('struct 数组字段拼接："%s"，建议直接索引 table 列', s)}; %#ok<AGROW>
            end
        end
    end
end

issues = table(issuesBuilder);
end



