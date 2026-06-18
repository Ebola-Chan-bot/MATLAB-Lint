function issues = mlint_noBuiltinShadowing(filePath)
%mlint_noBuiltinShadowing 检测与 MATLAB 内置/工具箱函数大小写不敏感重名的标识符。
% MATLAB 函数解析是大小写不敏感的，即变量 videoReader 也会遮蔽 VideoReader 函数。
% 自定义标识符应选择与任何 MATLAB 函数均不重名（大小写不敏感）的名称，且首字母大写。

if nargin == 0
    issues = "不要定义与 MATLAB 内置/工具箱函数大小写不敏感重名的标识符；建议改为首字母大写且不冲突的名称";
    return;
end

Tree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

ids = Tree.mtfind('Kind', 'ID');
if count(ids) == 0
    issues = table(issuesBuilder);
    return;
end

ix = ids.indices;
reported = dictionary;

for i = 1:numel(ix)
    nd = Tree.select(ix(i));
    name = string(nd.string);
    if strlength(name) == 0 ...
            || iIsCallTarget(nd) ...
            || iIsFieldName(nd) ...
            || iIsDotLeft(nd)
        continue;
    end
    % 排除 MATLAB 语言关键字（大小写不敏感）
    lowerName = lower(name);
    if ismember(lowerName, ["if","else","elseif","for","parfor","while","end", ...
            "switch","case","otherwise","try","catch","return","break","continue", ...
            "function","classdef","properties","methods","events","enumeration", ...
            "true","false","inf","nan","pi","i","j"])
        continue;
    end
    % 每个文件中同名标识符（大小写不敏感）只报一次
    if isKey(reported, char(lowerName))
        continue;
    end
    if ~iShadowsBuiltin(name)
        continue;
    end
    reported(char(name)) = true;
    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, double(nd.lineno), "mlint_noBuiltinShadowing", ...
        sprintf('标识符 "%s" 与 MATLAB 函数 "%s" 重名，建议改为大小写不敏感也不冲突的首字母大写标识符', ...
        name, char(which(name)))}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function tf = iIsCallTarget(idNode)
% 检查 ID 是否是函数调用的目标（如 sin(x) 中的 sin）
tf = false;
try
    p = Parent(idNode);
    if count(p) > 0 && strcmp(char(p.kind), 'CALL')
        tf = (count(Left(p)) > 0 && Left(p) == idNode);
    end
catch
end
end

% -------------------------------------------------------------------------
function tf = iIsFieldName(idNode)
% 检查 ID 是否是结构体字段名（如 s.field 中的 field）
tf = false;
try
    p = Parent(idNode);
    if count(p) > 0 && strcmp(char(p.kind), 'DOT')
        tf = (count(Right(p)) > 0 && Right(p) == idNode);
    end
catch
end
end

% -------------------------------------------------------------------------
function tf = iIsDotLeft(idNode)
% 检查 ID 是否是 DOT 链的左侧（如 MATLAB.DataTypes 中的 MATLAB）
tf = false;
try
    p = Parent(idNode);
    if count(p) > 0 && strcmp(char(p.kind), 'DOT')
        tf = (count(Left(p)) > 0 && Left(p) == idNode);
    end
catch
end
end

% -------------------------------------------------------------------------
function tf = iShadowsBuiltin(name)
% 大小写敏感检查：是否存在同名的 MATLAB 内置/工具箱函数。
% 变量遮蔽仅发生在精确大小写匹配时；大写变量 Missing 不遮蔽 missing 函数。
persistent cache;
if isempty(cache)
    cache = dictionary;
end

if isKey(cache, char(name))
    tf = cache(char(name));
    return;
end

% exist 本身是大小写不敏感的，所以只检查精确名称匹配
% 优先检查 builtin
if exist(name, 'builtin') == 5
    % 确认实际文件名大小写一致（exactName 记录真实名称，防 which 大小写不敏感）
    cache(char(name)) = true;
    tf = true;
    return;
end

% 再检查 MATLAB 路径函数
if exist(name, 'file') == 2
    w = which(name);
    if ~isempty(w) && startsWith(w, matlabroot)
        % 确认实际函数名与标识符大小写完全一致
        [~, fcnName, ~] = fileparts(w);
        if strcmp(fcnName, char(name))
            cache(char(name)) = true;
            tf = true;
            return;
        end
    end
end

cache(char(name)) = false;
tf = false;
end
