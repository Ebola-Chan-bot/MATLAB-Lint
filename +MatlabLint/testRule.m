function issues = testRule(ruleId, targetPath)
%TESTRULE 测试单条规则。
%
% 语法:
%   issues = MatlabLint.testRule(ruleId)
%   issues = MatlabLint.testRule(ruleId, targetPath)
%
% 输入:
%   ruleId     — 内置规则 ID（如 "mlint_noCatTableAppend"）或 .m 文件路径
%   targetPath — 被检查的文件或目录路径，省略则使用项目的 +MatlabLint/private/ 目录
%
% 返回:
%   issues — 表格（file, line, rule, message）

arguments
    ruleId (1,1) string
    targetPath (1,1) string = pwd
end

if ~isfolder(targetPath) && ~isfile(targetPath)
    error('MatlabLint:TestRuleTargetNotFound', '目标不存在: %s', targetPath);
end

% 解析规则函数句柄
ruleFn = iResolveRuleFn(ruleId);

% 收集文件
fileList = iDiscoverTestFiles(targetPath);

% 执行
allIssues = table;
for fi = 1:numel(fileList)
    fp = fileList(fi);
    try
        r = ruleFn(fp);
        if istable(r) && size(r, 1) > 0
            allIssues = [allIssues; r]; %#ok<AGROW>
        end
    catch ME
        warning('MatlabLint:TestRuleRunError', ...
            '%s 运行失败: %s\n%s', fp, ME.message, iFormatStack(ME));
    end
end

issues = allIssues;
end

function txt = iFormatStack(ME)
txt = "";
if isempty(ME.stack)
    return;
end
s = ME.stack(1);
txt = sprintf('at %s (%d)', s.name, s.line);
end

% -------------------------------------------------------------------------
function ruleFn = iResolveRuleFn(ruleId)
if isfile(ruleId)
    [d, f, ~] = fileparts(ruleId);
    if ~isempty(d), addpath(d); end
    ruleFn = str2func(f);
    return;
end

if startsWith(ruleId, 'mlint_')
    ruleFn = str2func(ruleId);
    return;
end

% 尝试作为相对路径在 private 目录中查找
privateDir = fullfile(fileparts(mfilename('fullpath')), 'private');
candidate = fullfile(privateDir, ruleId);
if isfile(candidate)
    ruleFn = str2func(extractBefore(ruleId, '.'));
    return;
end
candidate = fullfile(privateDir, ruleId + ".m");
if isfile(candidate)
    ruleFn = str2func(ruleId);
    return;
end

error('MatlabLint:TestRuleNotFound', '找不到规则: %s', ruleId);
end

% -------------------------------------------------------------------------
function fileList = iDiscoverTestFiles(targetPath)
if isfile(targetPath)
    fileList = targetPath;
    return;
end

% 目录：收集所有 .m 文件
d = dir(fullfile(targetPath, '*.m'));
fileList = strings(numel(d), 1);
for i = 1:numel(d)
    fileList(i) = string(fullfile(d(i).folder, d(i).name));
end
if isempty(fileList)
    error('MatlabLint:TestRuleNoFiles', '目录中无 .m 文件: %s', targetPath);
end
end

