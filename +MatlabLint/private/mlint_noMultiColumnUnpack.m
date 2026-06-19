function issues = mlint_noMultiColumnUnpack(filePath)
%mlint_noMultiColumnUnpack 基于 mtree 检测将表的多个列拆为独立变量。

if nargin == 0
    issues = "不应将表的多个列拆分为多个返回值（如 values=tbl.value; bodies=tbl.body;），应直接返回 table，并要求上游调用方改为按 table 使用";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 规则1：table2array / table2struct 拆表 ----
cix = FullTree.mtfind('Kind', 'CALL').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        nd = FullTree.select(cix(i));
        fn = iNodeText(Left(nd));
        if strcmpi(fn, "table2array")
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, nd.lineno, "mlint_noMultiColumnUnpack", ...
                "禁止通过 table2array 拆表；必须直接返回 table，并要求上游调用方调整为按 table 使用"}; %#ok<AGROW>
        elseif strcmpi(fn, "table2struct")
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, nd.lineno, "mlint_noMultiColumnUnpack", ...
                "禁止通过 table2struct 拆表；必须直接返回 table，并要求上游调用方改为按 table 使用"}; %#ok<AGROW>
        end
    end
end

% ---- 收集表变量名 ----
tblVarSet = iCollectTableVars(FullTree);

if isempty(tblVarSet)
    issues = table(issuesBuilder);
    return;
end

% ---- 规则2：对每个表变量，检测是否有多个列被拆到独立变量 ----
% 支持 DOT（tbl.col）、CELL（tbl{:, 'col'}）、SUBSCR（tbl(:, 'col')）三种语法
colUnpackRows = MATLAB.DataTypes.InsertiveTable();

% 统一处理 DOT / CELL / SUBSCR 三种列访问语法
for partKindCell = {'DOT', 'CELL', 'SUBSCR'}
    partKind = partKindCell{1};
    nodes = FullTree.mtfind('Kind', partKind);
    if count(nodes) == 0
        continue;
    end
    nix = nodes.indices;
    for i = 1:numel(nix)
        nd = FullTree.select(nix(i));
        leftId = Left(nd);
        if count(leftId) == 0 || ~strcmp(leftId.kind, 'ID')
            continue;
        end
        tblVar = leftId.string;
        if ~tblVarSet.isKey(tblVar) || (strcmp(partKind, 'DOT') && iIsInsideSubscr(nd)) ...
                || ~iIsOnRhs(nd)
            continue;
        end

        colName = iExtractColName(nd, partKind);
        if strlength(colName) == 0
            continue;
        end

        colUnpackRows(end+1, {'tbl','line','col'}) = ...
            {tblVar, nd.lineno, colName};
    end
end

% 每个表变量若有 ≥2 列被拆，报在第一行
colUnpackTable = table(colUnpackRows);
if height(colUnpackTable) == 0
    issues = table(issuesBuilder);
    return;
end
tblKeys = unique(colUnpackTable.tbl);
for ki = 1:numel(tblKeys)
    % 不转 string 会在这里复现真实错误：
    % mlint_noMultiColumnUnpack:80, == 数据类型无效。
    rows = colUnpackTable(colUnpackTable.tbl == string(tblKeys(ki)), :);
    if size(rows, 1) >= 2
        % 不转 char 会在 sprintf 处复现真实错误：
        % mlint_noMultiColumnUnpack:84, sprintf 不支持 cell 输入。
        keyText = char(string(tblKeys(ki)));
        colsText = char(strjoin(string(unique(rows.col)), ", "));
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, rows.line(1), "mlint_noMultiColumnUnpack", ...
            sprintf('不应将表 "%s" 的多个列（%s）拆分为独立变量；必须直接返回 table，并要求上游调用方调整为按 table 使用', ...
            keyText, colsText)}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function tblVarSet = iCollectTableVars(FullTree)
tblVarSet = configureDictionary('string', 'logical');

eix = FullTree.mtfind('Kind', 'EQUALS').indices;
if isempty(eix)
    return;
end

for i = 1:numel(eix)
    nd = FullTree.select(eix(i));
    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(lhs.kind, 'ID')
        continue;
    end
    if iIsTableConstructor(Right(nd))
        tblVarSet(lhs.string) = true;
    end
end
end

% -------------------------------------------------------------------------
function tf = iIsTableConstructor(node)
tf = false;
if strcmp(node.kind, 'CALL')
    fn = iNodeText(Left(node));
    tf = strcmpi(fn, "table") || strcmpi(fn, "MATLAB.DataTypes.InsertiveTable");
end
end

% -------------------------------------------------------------------------
function tf = iIsInsideSubscr(nd)
tf = false;
while count(Parent(nd)) > 0
    if strcmp(Parent( nd ).kind, 'SUBSCR')
        tf = true;
        return;
    end
    nd = Parent(nd);
end
end

% -------------------------------------------------------------------------
function tf = iIsOnRhs(nd)
tf = false;
p = Parent(nd);
while count(p) > 0
    pk = p.kind;
    if strcmp(pk, 'EQUALS')
        % nd 必须在 EQUALS 的 Right 子树中（非 Left）
        tf = iIsDescendantOf(Right(p), nd);
        return;
    end
    if strcmp(pk, 'FUNCTION')
        return;
    end
    p = Parent(p);
end
end

% -------------------------------------------------------------------------
function col = iExtractColName(node, nodeKind)
% 从 DOT/CELL/SUBSCR 节点提取列标识。
% DOT:  Right 为字段名 ID（如 tbl.colname）
% CELL: Right→Next 为列名字符串（如 tbl{:, 'colname'}）
% SUBSCR: Right→Arg 链中找字符串字面量
col = "";
node = Right(node);
if count(node) == 0
    return;
end

if strcmp(nodeKind, 'DOT')
    nk = node.kind;
    if strcmp(nk, 'ID') || strcmp(nk, 'FIELD')
        col = node.string;
    else
        col = iNodeText(node);
    end
    return;
end

% CELL: Right 是 COLON(:)，列名在 Next(Right) 中
if strcmp(nodeKind, 'CELL')
    if strcmp(node.kind, 'COLON')
        col = Next(node);
        if count(col) > 0
            col = iNodeText( col );
            if ~isempty(col) && (col(1) == '"' || col(1) == '''')
                col = col(2:end-1);
            end
            if strlength(col) == 0
                col = "";
            end
        end
    end
    return;
end

% SUBSCR: 圆括号索引，如 tbl(:, 'colname')
if strcmp(nodeKind, 'SUBSCR') && count(Arg(node)) > 0
    argNode = Arg(node);
    while count(argNode) > 0
        col = iNodeText( argNode );
        if ~isempty(col) && (col(1) == '"' || col(1) == '''')
            col = col(2:end-1);
        end
        if strlength(col) > 0 && ~strcmp(col, ":")
            return;
        end
        col = "";
        try
            argNode = Next(argNode);
        catch
            break;
        end
    end
end
end

% -------------------------------------------------------------------------
function txt = iNodeText(node)
txt = "";
if count(node) ~= 1
    return;
end
try
    txt = strtrim(node.tree2str);
catch
    txt = "";
end
end

% -------------------------------------------------------------------------
function tf = iIsDescendantOf(AncestorNode, target)
tf = false;
if count(AncestorNode) == 0 || count(target) == 0
    return;
end
tf = lefttreepos(target) >= lefttreepos(AncestorNode) ...
  && righttreepos(target) <= righttreepos(AncestorNode);
end
