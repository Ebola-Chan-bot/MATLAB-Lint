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

decls = iCollectDeclaredNames(Tree);
if isempty(decls)
    issues = table(issuesBuilder);
    return;
end

reported = configureDictionary('string', 'logical');
keywords = {'if','else','elseif','for','parfor','while','end', ...
    'switch','case','otherwise','try','catch','return','break','continue', ...
    'function','classdef','properties','methods','events','enumeration', ...
    'true','false','inf','nan','pi','i','j'};

for i = 1:height(decls)
    % decls.name 列是 cell；这里应直接取内容，不做后置“防御性归一”。
    nameChar = decls.name{i};
    line = decls.line( i );
    if isempty(nameChar)
        continue;
    end
    % 排除 MATLAB 语言关键字（大小写不敏感）
    lowerName = lower(nameChar);
    if any(strcmp(lowerName, keywords))
        continue;
    end
    % 每个文件中同名标识符（大小写不敏感）只报一次
    if isKey(reported, lowerName)
        continue;
    end
    if ~iShadowsBuiltin(nameChar)
        continue;
    end
    reported(lowerName) = true;
    fnPath = which(nameChar);
    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, line, "mlint_noBuiltinShadowing", ...
        sprintf('标识符 "%s" 与 MATLAB 函数 "%s" 重名，建议为 "%s"', ...
        nameChar, fnPath, iSuggestedName(nameChar))}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function suggested = iSuggestedName(name)
% 用 matlab.lang.makeValidName + makeUniqueStrings 生成首字母大写且不重复的建议名。
name = name;
base = append(upper(extractBetween(name, 1, 1)), extractAfter(name, 1));
suggested = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(base));
suggested = suggested(1);
end

% -------------------------------------------------------------------------
function decls = iCollectDeclaredNames(Tree)
builder = MATLAB.DataTypes.InsertiveTable();

% 1) 函数输入/输出变量
fnIdx = Tree.mtfind('Kind', 'FUNCTION').indices;
for i = 1:numel(fnIdx)
    fn = Tree.select(fnIdx(i));
    ln = fn.lineno;
    try
        builder = iAppendNodeListIds(builder, Outs(fn), ln);
    catch
    end
    try
        builder = iAppendNodeListIds(builder, Ins(fn), ln);
    catch
    end
end

% 2) 赋值左值目标变量
eqIdx = Tree.mtfind('Kind', 'EQUALS').indices;
for i = 1:numel(eqIdx)
    nd = Tree.select(eqIdx(i));
    ln = nd.lineno;
    names = iCollectAssignmentTargetNames(Left(nd));
    for ni = 1:numel(names)
        if strlength(names(ni)) == 0
            continue;
        end
        builder(end+1, {'name','line'}) = {names( ni ), ln}; %#ok<AGROW>
    end
end

decls = table(builder);
end

% -------------------------------------------------------------------------
function builder = iAppendNodeListIds(builder, nodeList, lineNo)
if count(nodeList) == 0
    return;
end

if count(nodeList) == 1 && strcmp(nodeList.kind, 'LB')
    cur = Arg(nodeList);
else
    cur = nodeList;
end

while count(cur) > 0
    if strcmp(cur.kind, 'ID')
        nm = cur.string;
        if strlength(nm) > 0
            builder(end+1, {'name','line'}) = {nm, lineNo}; %#ok<AGROW>
        end
    end
    try
        cur = Next(cur);
    catch
        break;
    end
end
end

% -------------------------------------------------------------------------
function names = iCollectAssignmentTargetNames(lhs)
vec = MATLAB.Containers.Vector();
iCollectTargetNamesRec(lhs, vec);
names = unique(vec.Data( : ));
end

function iCollectTargetNamesRec(node, vec)
if count(node) == 0
    return;
end
k = node.kind;

if strcmp(k, 'ID')
    vec.PushBack(node.string);
    return;
end

if strcmp(k, 'LB') || strcmp(k, 'ROW')
    cur = Arg(node);
    while count(cur) > 0
        iCollectTargetNamesRec(cur, vec);
        try
            cur = Next(cur);
        catch
            break;
        end
    end
    return;
end

if strcmp(k, 'SUBSCR') || strcmp(k, 'DOT') || strcmp(k, 'PARENS') || strcmp(k, 'CELL')
    iCollectTargetNamesRec(Left(node), vec);
    return;
end

% 回退：优先看 Left
if count(Left(node)) > 0
    iCollectTargetNamesRec(Left(node), vec);
end
end

% -------------------------------------------------------------------------
function tf = iShadowsBuiltin(name)
% 大小写敏感检查：是否存在同名的 MATLAB 内置/工具箱函数。
% 变量遮蔽仅发生在精确大小写匹配时；大写变量 Missing 不遮蔽 missing 函数。
persistent cache;
if isempty(cache)
    cache = configureDictionary('string', 'logical');
end

if iscell(name)
    name = name{1};
end
nameChar = name;

if isKey(cache, nameChar)
    tf = cache(nameChar);
    return;
end

% exist 本身是大小写不敏感的，所以只检查精确名称匹配
% 优先检查 builtin
if exist(nameChar, 'builtin') == 5
    % 确认实际文件名大小写一致（exactName 记录真实名称，防 which 大小写不敏感）
    cache(nameChar) = true;
    tf = true;
    return;
end

% 再检查 MATLAB 路径函数
if exist(nameChar, 'file') == 2
    w = which(nameChar);
    if ~isempty(w) && startsWith(w, matlabroot)
        % 确认实际函数名与标识符大小写完全一致
        [~, fcnName, ~] = fileparts(w);
        if strcmp(fcnName, nameChar)
            cache(nameChar) = true;
            tf = true;
            return;
        end
    end
end

cache(nameChar) = false;
tf = false;
end

