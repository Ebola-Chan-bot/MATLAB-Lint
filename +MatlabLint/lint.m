%[text] 扫描文件或目录并执行规则。
%[text] ## 语法
%[text] ```matlabCodeExample
%[text] issues = MatlabLint.lint();
%[text] issues = MatlabLint.lint(targetPath);
%[text] issues = MatlabLint.lint(cfg);
%[text] issues = MatlabLint.lint(targetPath, cfg);
%[text] issues = MatlabLint.lint(cfg, targetPath);
%[text] ```
%[text] ## 输入参数
%[text] targetPath(1,1)string
%[text] cfg
%[text] ## 返回值
%[text] issues
function issues = lint(varargin)

targetPath = ".";
cfgOverride = [];
for i = 1:nargin
    v = varargin{i};
    if isstruct(v)
        cfgOverride = v;
    else
        targetPath = v;
    end
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

%[appendix]{"version":"1.0"}
%---
