function issues = mlint_noMultiColumnUnpack(filePath)
%mlint_noMultiColumnUnpack 基于 mtree 检测将表的多个列拆为独立变量。

if nargin == 0
    issues = "不应将表的多个列拆分为多个返回值（如 values=tbl.value; bodies=tbl.body;），应直接返回 table，并要求上游调用方改为按 table 使用";
    return;
end

FullTree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

% ---- 规则1：table2array 拆表 ----
cix = FullTree.mtfind('Kind', 'CALL').indices;
if ~isempty(cix)
    for i = 1:numel(cix)
        nd = FullTree.select(cix(i));
        if strcmpi(string(Left(nd).tree2str), "table2array")
            issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                filePath, double(nd.lineno), "mlint_noMultiColumnUnpack", ...
                "禁止通过 table2array 拆表；必须直接返回 table，并要求上游调用方调整为按 table 使用"}; %#ok<AGROW>
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
% key=表变量名, value=struct('lines',[],'cols',cell(1,0))
colUnpackLines = dictionary;

% 统一处理 DOT / CELL / SUBSCR 三种列访问语法
for partKind = ["DOT", "CELL", "SUBSCR"]
    nodes = FullTree.mtfind('Kind', partKind);
    if count(nodes) == 0
        continue;
    end
    nix = nodes.indices;
    for i = 1:numel(nix)
        nd = FullTree.select(nix(i));
        leftId = Left(nd);
        if count(leftId) == 0 || ~strcmp(char(leftId.kind), 'ID')
            continue;
        end
        tblVar = string(leftId.string);
        if ~tblVarSet.isKey(tblVar) || (partKind == "DOT" && iIsInsideSubscr(nd)) ...
                || ~iIsOnRhs(nd)
            continue;
        end

        colName = iExtractColName(nd, partKind);
        if strlength(colName) == 0
            continue;
        end

        tblKey = char(tblVar);
        if ~isKey(colUnpackLines, tblKey)
            colUnpackLines(tblKey) = struct('lines', zeros(1,0), 'cols', {{}});
        end
        acc = colUnpackLines(tblKey);
        acc.lines(end+1) = double(nd.lineno);
        acc.cols{end+1} = char(colName);
        colUnpackLines(tblKey) = acc;
    end
end

% 每个表变量若有 ≥2 列被拆，报在第一行
tblKeys = colUnpackLines.keys;
for ki = 1:numel(tblKeys)
    acc = colUnpackLines(tblKeys{ki});
    if numel(acc.lines) >= 2
        issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
            filePath, acc.lines(1), "mlint_noMultiColumnUnpack", ...
            sprintf('不应将表 "%s" 的多个列（%s）拆分为独立变量；必须直接返回 table，并要求上游调用方调整为按 table 使用', ...
            tblKeys{ki}, strjoin(unique(string(acc.cols)), ", "))}; %#ok<AGROW>
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function tblVarSet = iCollectTableVars(FullTree)
tblVarSet = dictionary;

eix = FullTree.mtfind('Kind', 'EQUALS').indices;
if isempty(eix)
    return;
end

for i = 1:numel(eix)
    nd = FullTree.select(eix(i));
    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
        continue;
    end
    if iIsTableConstructor(Right(nd))
        tblVarSet(char(string(lhs.string))) = true;
    end
end
end

% -------------------------------------------------------------------------
function tf = iIsTableConstructor(node)
tf = false;
if char(node.kind) == "CALL"
    tf = strcmpi(string(Left(node).tree2str), "table") ...
      || strcmpi(string(Left(node).tree2str), "MATLAB.DataTypes.InsertiveTable");
end
end

% -------------------------------------------------------------------------
function tf = iIsInsideSubscr(nd)
tf = false;
while count(Parent(nd)) > 0
    if strcmp(char(Parent(nd).kind), 'SUBSCR')
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
    pk = char(p.kind);
    if pk == "EQUALS"
        % nd 必须在 EQUALS 的 Right 子树中（非 Left）
        tf = iIsDescendantOf(Right(p), nd);
        return;
    end
    if pk == "FUNCTION"
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

if nodeKind == "DOT"
    col = string(node.tree2str);
    return;
end

% CELL: Right 是 COLON(:)，列名在 Next(Right) 中
if nodeKind == "CELL"
    if char(node.kind) == "COLON"
        col = Next(node);
        if count(col) > 0
            col = char(strtrim(string(col.tree2str)));
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
if nodeKind == "SUBSCR" && count(Arg(node)) > 0
    col = Arg(node);
    while count(col) > 0
        col = char(strtrim(string(col.tree2str)));
        if ~isempty(col) && (col(1) == '"' || col(1) == '''')
            col = col(2:end-1);
        end
        if strlength(col) > 0 && ~strcmp(col, ":")
            return;
        end
        col = "";
        try
            col = Next(col);
        catch
            break;
        end
    end
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