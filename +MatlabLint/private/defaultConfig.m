function cfg = defaultConfig()
%DEFAULTCONFIG 配置参考模板（不会被自动加载）。
% 复制此文件到用户级或项目级 .matlablint.json 使用。

cfg = struct( ...
    'IncludePattern', "**/*.m", ...
    'Exclude', ["**/resources/**", "**/.git/**"], ...
    'OutputToConsole', true);

ids = fieldnames(builtinRuleRegistry());
if isempty(ids)
    cfg.Rules = struct('Id', {}, 'Enabled', {});
    return;
end

cfg.Rules = cell2struct([cellstr(ids), num2cell(true(numel(ids), 1))], {'Id', 'Enabled'}, 2);
end

