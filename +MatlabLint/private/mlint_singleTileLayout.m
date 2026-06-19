function issues = mlint_singleTileLayout(filePath)
%mlint_singleTileLayout tiledlayout 仅一个 tile — 建议去掉 layout 直接画图。

if nargin == 0
    issues = "tiledlayout 仅一个 tile 时建议去掉 layout";
    return;
end
AllLines = splitlines(fileread( filePath ));

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

nLines = numel(AllLines);
for i = 1:nLines
    s = strtrim(AllLines( i ));
    if isempty(s) || startsWith(s, '%')
        continue;
    end
    cs = codeLine(s);
    if isempty(cs) || ~(contains(cs, "tiledlayout") && contains(cs, ", 1, 1)"))
        continue;
    end
    tileCount = 0;
    for j = i+1:nLines
        sj = strtrim(AllLines( j ));
        if isempty(sj) || startsWith(sj, '%')
            continue;
        end
        if contains(sj, "nexttile(")
            tileCount = tileCount + 1;
            if tileCount > 1
                break;
            end
        end
    end
    if tileCount <= 1
        issuesBuilder(end+1, {'file','line','rule','message'}) = {filePath, i, "mlint_singleTileLayout", ...
            sprintf('tiledlayout 仅有 1 个 tile（%s），建议移除 layout 直接绘图', s)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end



