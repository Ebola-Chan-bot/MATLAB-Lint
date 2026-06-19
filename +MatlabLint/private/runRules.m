function issues = runRules(fileList, rules)
%RUNRULES 按历史累计耗时降序执行所有规则；文件级并行执行。

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
    timingMap = configureDictionary('string', 'double');
    for ti = 1:numel(db.Rules)
        timingMap(db.Rules( ti ).id) = db.Rules(ti).totalSec;
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

% 按规则执行；每条规则对文件列表使用并行。
allResults = cell(nRules, 1);
ruleTimes = zeros(nRules, 1);

for r = 1:nRules
    t0 = tic;
    fn = ruleFns{r};
    perFile = cell(nFiles, 1);
    parfor f = 1:nFiles
        out = fn(fileList{f});
        perFile{f} = out;
    end

    localBuilder = MATLAB.DataTypes.InsertiveTable();
    for f = 1:nFiles
        out = perFile{f};
        if isempty(out)
            continue;
        end
        for ri = 1:height(out)
            fileVal = iTextScalar(out.file(ri));
            ruleVal = iTextScalar(out.rule(ri));
            msgVal = iTextScalar(out.message(ri));
            localBuilder(end+1, {'file','line','rule','message'}) = ...
                {fileVal, out.line(ri), ruleVal, msgVal};
        end
    end
    allResults{r} = localBuilder;
    ruleTimes(r) = toc(t0);
end

% 合并所有规则的结果
issuesBuilder = MATLAB.DataTypes.InsertiveTable();
for r = 1:nRules
    tbl = allResults{r};
    for ri = 1:height(tbl)
        fileVal = iTextScalar(tbl.file(ri));
        ruleVal = iTextScalar(tbl.rule(ri));
        msgVal = iTextScalar(tbl.message(ri));
        issuesBuilder(end+1, {'file','line','rule','message'}) = ...
            {fileVal, tbl.line(ri), ruleVal, msgVal};
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

% -------------------------------------------------------------------------
function txt = iTextScalar(v)
if iscell(v)
    % 不先解 cell 会在 InsertiveTable 写回时复现真实错误：
    % runRules:54 -> 无法将 string 转为 cell（RawTable 赋值失败）。
    v = v{1};
end
if isstring(v)
    % 统一到 char 标量以避免 RawTable 类型转换失败（同上错误链）。
    txt = char(v);
elseif ischar(v)
    txt = v;
else
    % 非文本类型统一转 char，避免写回 RawTable 时再触发类型转换错误（同上错误链）。
    txt = char(string(v));
end
end

