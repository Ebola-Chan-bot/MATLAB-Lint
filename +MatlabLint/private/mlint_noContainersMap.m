function issues = mlint_noContainersMap(filePath)
%mlint_noContainersMap 建议用 dictionary 替代 containers.Map。

if nargin == 0
    issues = "建议用 dictionary 替代 containers.Map";
    return;
end
lines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(lines)
    s = char(lines(i));
    if isempty(strtrim(s)) || startsWith(strtrim(s), '%')
        continue;
    end

    code = char(MatlabLint.stripStringLiterals(strtrim(s)));
    commentPos = strfind(code, '%');
    if ~isempty(commentPos)
        code = code(1:commentPos(1)-1);
    end

    if iHasContainersMapCtor(code)
        issuesBuilder = appendIssue(issuesBuilder, makeIssue(filePath, i, "mlint_noContainersMap", ...
            sprintf('建议使用 dictionary 替代 containers.Map：%s', s))); %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

function tf = iHasContainersMapCtor(code)
tf = false;
s = lower(strtrim(string(code)));
idx = strfind(char(s), 'containers.map');
if isempty(idx)
    return;
end

txt = char(s);
n = numel(txt);
for k = 1:numel(idx)
    p = idx(k);

    prev = ' ';
    if p > 1
        prev = txt(p-1);
    end
    if isstrprop(prev, 'alphanum') || prev == '_'
        continue;
    end

    j = p + strlength("containers.map");
    while j <= n && isspace(txt(j))
        j = j + 1;
    end
    if j <= n && txt(j) == '('
        tf = true;
        return;
    end
end
end



