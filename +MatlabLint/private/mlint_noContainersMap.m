function issues = mlint_noContainersMap(filePath)
%mlint_noContainersMap 建议用 dictionary 替代 containers.Map。

if nargin == 0
    issues = "建议用 dictionary 替代 containers.Map";
    return;
end
AllLines = splitlines(string(fileread(filePath)));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for i = 1:numel(AllLines)
    s = char(AllLines(i));
    if isempty(strtrim(s)) || startsWith(strtrim(s), '%')
        continue;
    end

    code = codeLine(strtrim(s));
    if isempty(code)
        continue;
    end

    lowerCode = lower(strtrim(string(code)));
    idx = strfind(char(lowerCode), 'containers.map');
    if ~isempty(idx)
        txt = char(lowerCode);
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
                issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_noContainersMap", ...
                    sprintf('建议使用 dictionary 替代 containers.Map：%s', s)}; %#ok<AGROW>
                break;
            end
        end
    end
end

issues = table(issuesBuilder);
end



