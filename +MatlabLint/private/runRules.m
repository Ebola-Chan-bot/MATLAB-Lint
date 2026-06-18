function issues = runRules(fileList, rules)
%RUNRULES 按历史累计耗时降序并行执行所有规则。

nFiles = numel(fileList);
nRules = numel(rules);

% 预收集规则句柄和 ID（parfor 外需用切片变量）
ruleFns = cell(nRules, 1);
ruleIds = cell(nRules, 1);
for r = 1:nRules
    ruleFns{r} = rules(r).fn;
    ruleIds{r} = rules(r).id;
end

% 按历史累计耗时降序排序（最耗时的规则先执行）
db = ruleTimingDB('load');
if isfield(db, 'Rules') && ~isempty(db.Rules)
    timingMap = dictionary;
    for ti = 1:numel(db.Rules)
        timingMap(char(db.Rules(ti).id)) = db.Rules(ti).totalSec;
    end

    weights = zeros(nRules, 1);
    for r = 1:nRules
        if isKey(timingMap, ruleIds{r})
            weights(r) = timingMap(ruleIds{r});
        end
    end
    [~, order] = sort(weights, 'descend');
    ruleFns = ruleFns(order);
    ruleIds = ruleIds(order);
end

% parfor 按规则并行：每个 worker 处理一个规则在所有文件上的结果
allResults = cell(nRules, 1);
ruleTimes = zeros(nRules, 1);

parfor r = 1:nRules
    localBuilder = MATLAB.DataTypes.InsertiveTable();
    fn = ruleFns{r};
    for f = 1:nFiles
        out = fn(fileList{f});
        for ri = 1:height(out)
            localBuilder(end+1, {'file','line','rule','message'}) = ...
                {char(string(out.file(ri))), out.line(ri), char(string(out.rule(ri))), char(string(out.message(ri)))};
        end
    end
    allResults{r} = localBuilder;
    ruleTimes(r) = toc;
end

% 合并所有规则的结果
issuesBuilder = MATLAB.DataTypes.InsertiveTable();
for r = 1:nRules
    tbl = allResults{r};
    for ri = 1:height(tbl)
        issuesBuilder(end+1, {'file','line','rule','message'}) = ...
            {char(string(tbl.file(ri))), tbl.line(ri), char(string(tbl.rule(ri))), char(string(tbl.message(ri)))};
    end
end

% 更新累计耗时（parfor 外，避免并发写文件）
for r = 1:nRules
    if ruleTimes(r) > 0
        ruleTimingDB('update', ruleIds{r}, ruleTimes(r));
    end
end

issues = table(issuesBuilder);
end

