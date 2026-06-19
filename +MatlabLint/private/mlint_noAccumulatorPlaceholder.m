function issues = mlint_noAccumulatorPlaceholder(filePath)
%mlint_noAccumulatorPlaceholder 基于 mtree 检测累积器类占位初始化。
% 豁免：
% 1) 简单空表初始化 table()
% 2) 变量后续参与 isempty(var) 决策
%
% 检测模式：
% - 直接占位赋值: v = []; v = {}; v = zeros(1,0); v = strings(0,1); 等
% - struct 字段占位: struct('field1', zeros(1,0), 'field2', {{}}) 等

if nargin == 0
    issues = "禁止累积器类占位空初始化（豁免：table() 与 isempty 决策变量）；建议使用 MATLAB.DataTypes.InsertiveTable、MATLAB.DataTypes.ArrayBuilder 或 MATLAB.Containers.Vector";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% 收集 isempty 豁免变量
isemptyVars = iCollectIsemptyVars(FullTree);

% 类型 A：直接占位赋值 (v = placeholder)
placeholderVars = iFindPlaceholderInits(FullTree);
for pi = 1:size(placeholderVars, 1)
    vn = char(placeholderVars.var(pi));
    initLine = placeholderVars.line(pi);
    initStmt = placeholderVars.stmt(pi);
    initIdx = placeholderVars.eqIdx(pi);
    
    if ~isempty(isemptyVars) && any(isemptyVars == lower(vn))
        continue;
    end
    if iHasAccumulatorUse(FullTree, vn, initIdx)
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, initLine, "mlint_noAccumulatorPlaceholder", ...
            sprintf('避免使用累积器占位空初始化：%s。建议改用 MATLAB.DataTypes.InsertiveTable、MATLAB.DataTypes.ArrayBuilder 或 MATLAB.Containers.Vector。', ...
            strtrim(initStmt))}; %#ok<AGROW>
    end
end

% 类型 B：struct 字面量含占位字段 — 直接报警（无需确认累积使用）
structPlaceholders = iFindStructPlaceholders(FullTree);
for pi = 1:size(structPlaceholders, 1)
    initLine = structPlaceholders.line(pi);
    initStmt = structPlaceholders.stmt(pi);
    issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
        filePath, initLine, "mlint_noAccumulatorPlaceholder", ...
        sprintf('避免使用累积器占位空初始化：%s。建议改用 MATLAB.DataTypes.InsertiveTable（每个 struct 字段一列）。', ...
        strtrim(initStmt))}; %#ok<AGROW>
end

issues = table(issuesBuilder);
end

% =========================================================================
function tvars = iCollectIsemptyVars(FullTree)
tvars = strings(1, 0);
cix = FullTree.mtfind('Kind', 'CALL').indices;
if isempty(cix), return; end
for i = 1:numel(cix)
    nd = FullTree.select(cix(i));
    fn = Left( nd ).tree2str;
    if ~strcmpi(strtrim(fn), 'isempty'), continue; end
    child = Right(nd);
    if count(child) == 1 && strcmp(child.kind, 'ID')
        tvars(end+1) = lower(child.string); %#ok<AGROW>
    end
end
if ~isempty(tvars), tvars = unique(tvars); end
end

% =========================================================================
function result = iFindPlaceholderInits(FullTree)
% 返回 table(var, line, stmt, eqIdx)
builder = MATLAB.DataTypes.InsertiveTable();
eix = FullTree.mtfind('Kind', 'EQUALS').indices;
for i = 1:numel(eix)
    nd = FullTree.select(eix(i));
    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(lhs.kind, 'ID'), continue; end
    if iIsPlaceholder(Right(nd))
        builder(end+1, {'var','line','stmt','eqIdx'}) = { ...
            lhs.string, double(nd.lineno), nd.tree2str, eix(i)}; %#ok<AGROW>
    end
end
result = table(builder);
end

% =========================================================================
function tf = iIsPlaceholder(node)
tf = false;
if count(node) == 0, return; end
k = node.kind;

if strcmp(k, 'EMPTY')
    tf = true; return;
end

if strcmp(k, 'CELL')
    % {} 或 {{}}
    if count(node) == 0
        tf = true; return;
    end
    child = Arg(node);
    if count(child) == 1 && strcmp(child.kind, 'CELL') && count(child) == 0
        tf = true; return;
    end
    return;
end

if strcmp(k, 'CALL')
    tf = iIsPlaceholderCall(node);
    return;
end

if strcmp(k, 'DOT')
    % ClassName.empty（无括号调用）
    try
        if strcmpi(Right( node ).tree2str, 'empty')
            tf = true;
        end
    catch
    end
    return;
end
end

% =========================================================================
function tf = iIsPlaceholderCall(node)
tf = false;
try
    fn = lower(strtrim(Left( node ).tree2str));
catch
    return;
end
firstArg = Right(node);

switch fn
    case {'zeros', 'ones', 'nan', 'cell', 'strings'}
        % 任意维度为 0
        tf = iAnyArgIsZero(firstArg);
        return;
    case 'repmat'
        if strcmp(firstArg.kind, 'EMPTY')
            tf = true;
        end
        return;
    case 'struct'
        % struct 字段值含占位符
        tf = iStructHasPlaceholderField(firstArg);
        return;
    case 'table'
        tf = iTableHasZeroSize(firstArg);
        return;
end
end

% =========================================================================
function tf = iAnyArgIsZero(node)
tf = false;
cur = node;
while count(cur) > 0
    if strcmp(strtrim(cur.tree2str), '0')
        tf = true; return;
    end
    cur = Next(cur);
end
end

% =========================================================================
function tf = iStructHasPlaceholderField(node)
% struct(name1, val1, name2, val2, ...) — 偶数位置是值
tf = false;
cur = node;
idx = 1;
while count(cur) > 0
    if mod(idx, 2) == 0 && iIsPlaceholder(cur)
        tf = true; return;
    end
    cur = Next(cur);
    idx = idx + 1;
end
end

% =========================================================================
function tf = iTableHasZeroSize(node)
tf = false;
cur = node;
while count(cur) > 0
    s = lower(strtrim(cur.tree2str));
    s = erase(erase(s, '"'), "'");
    if strcmp(s, 'size') || strcmp(s, 'sizes')
        nxt = Next(cur);
        if count(nxt) > 0
            nxtKind = nxt.kind;
            if strcmp(nxtKind, 'ROW') || strcmp(nxtKind, 'COL')
                child = Arg(nxt);
                if count(child) > 0 && strcmp(strtrim(child.tree2str), '0')
                    tf = true; return;
                end
            end
        end
    end
    cur = Next(cur);
end
end

% =========================================================================
function result = iFindStructPlaceholders(FullTree)
% 扫描所有 struct(...) 调用，若任一字段值为占位符则报告
builder = MATLAB.DataTypes.InsertiveTable();
cix = FullTree.mtfind('Kind', 'CALL').indices;
for i = 1:numel(cix)
    nd = FullTree.select(cix(i));
    try
        fn = strtrim(Left( nd ).tree2str);
    catch
        continue;
    end
    if ~strcmpi(fn, 'struct'), continue; end
    firstArg = Right(nd);
    if iStructHasPlaceholderField(firstArg)
        builder(end+1, {'line','stmt'}) = { ...
            double(nd.lineno), nd.tree2str}; %#ok<AGROW>
    end
end
result = table(builder);
end

% =========================================================================
function tf = iHasAccumulatorUse(FullTree, varName, initIdx)
tf = false;
eix = FullTree.mtfind('Kind', 'EQUALS').indices;
for i = 1:numel(eix)
    nd = FullTree.select(eix(i));
    if lefttreepos(nd) <= lefttreepos(FullTree.select(initIdx)), continue; end
    lhs = Left(nd);
    if count(lhs) == 0, continue; end
    if iLhsHasEndIndexOnVar(lhs, varName)
        tf = true; return;
    end
end
end

% =========================================================================
function tf = iLhsHasEndIndexOnVar(lhs, varName)
% 检查 LHS 是否是对 varName 的 end+1 型累积写入
% 支持: v(end+1), v.field(end+1), v{end+1}, v.field{end+1}
tf = false;
k = lhs.kind;

if strcmp(k, 'SUBSCR') || strcmp(k, 'CELL')
    if iLeftResolvesToVar(Left(lhs), varName) ...
            && contains(strtrim(Right( lhs ).tree2str), 'end')
        tf = true; return;
    end
end
end

% =========================================================================
function tf = iLeftResolvesToVar(node, varName)
% 沿 Left 链穿过 DOT/SUBSCR/CELL 直到 ID，检查是否等于 varName
if count(node) == 0, tf = false; return; end
k = node.kind;
if strcmp(k, 'ID')
    tf = strcmp(node.string, varName);
    return;
end
if ismember(k, {'DOT', 'SUBSCR', 'CELL', 'PARENS'})
    tf = iLeftResolvesToVar(Left(node), varName);
    return;
end
tf = false;
end

