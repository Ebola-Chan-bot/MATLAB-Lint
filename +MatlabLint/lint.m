function issues = lint(targetPath, cfgOverride)
%MATLABLINT 入口函数：扫描文件或目录并执行规则。
% issues = MatlabLint.lint(targetPath)
% issues = MatlabLint.lint(targetPath, cfg)

if nargin < 2
    cfgOverride = [];
end

targetPath = string(targetPath);
if ~isscalar(targetPath)
    error('MatlabLint:InvalidTargetPath', 'targetPath 必须是 string 标量。');
end
if ~isempty(cfgOverride) && ~isstruct(cfgOverride)
    error('MatlabLint:InvalidConfigOverride', 'cfg 必须是 struct。');
end

cfg = loadConfigLayers(targetPath);
if ~isempty(cfgOverride)
    cfg = mergeStruct(cfg, cfgOverride);
end

% 操作级兜底：未配置时默认控制台输出、不排除路径
if ~isfield(cfg, 'OutputToConsole')
    cfg.OutputToConsole = true;
end
if ~isfield(cfg, 'Exclude')
    cfg.Exclude = {};
end

issues = runRules(discoverFiles(targetPath, cfg), resolveEnabledRules(cfg));

if cfg.OutputToConsole
    reportIssues(issues);
end
end
