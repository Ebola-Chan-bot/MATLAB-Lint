function issues = runRules(fileList, rules)
%RUNRULES 对所有文件执行所有启用规则。

issuesBuilder = MATLAB.DataTypes.InsertiveTable();

for f = 1:numel(fileList)
    for r = 1:numel(rules)
        out = rules(r).fn(fileList(f));
        for ri = 1:height(out)
            issuesBuilder(end+1, {'file','line','rule','message'}) = ...
                {out.file(ri), out.line(ri), out.rule(ri), out.message(ri)};
        end
    end
end

issues = table(issuesBuilder);
end

