function issues = mlint_mergeSyncAccumulatorPairs(filePath)
%mlint_mergeSyncAccumulatorPairs 基于 mtree 检测同步累积变量对可合并。
% 规则：仅依赖“累积同步”，不依赖 Harvest/Data 收割。
% 同步判定：同作用域内同构造器变量，追加次数相同且每次追加在节点序上相邻。

if nargin == 0
    issues = "同步追加的多个 ArrayBuilder/Vector 应合并为 MATLAB.DataTypes.InsertiveTable（不依赖收割判断）";
    return;
end

Tree = List(mtree(filePath, '-file'));
issuesBuilder = MATLAB.DataTypes.InsertiveTable();

fnNodes = Tree.mtfind('Kind', 'FUNCTION');
if count(fnNodes) == 0
    scopes = iMakeScriptScope(Tree);
else
    scopes = iMakeFunctionScopes(Tree, fnNodes.indices);
end

for si = 1:numel(scopes)
    sc = scopes(si);

    vars = iCollectBuilderVarsInScope(Tree, sc);
    if numel(vars) < 2
        continue;
    end

    events = iCollectAppendEventsInScope(Tree, sc, vars);
    if isempty(events)
        continue;
    end

    [~, order] = sort([events.pos]);
    events = events(order);

    for ei = 1:numel(events)
        events(ei).eventOrder = ei;
    end

    for vi = 1:numel(vars)-1
        for vj = vi+1:numel(vars)
            pair = iBuildPair(events, vars(vi), vars(vj));
            if iIsSynchronousPair(pair)
                issuesBuilder(end+1, {'file','line','rule','message'}) = { ...
                    filePath, pair.firstLine, "mlint_mergeSyncAccumulatorPairs", ...
                    sprintf('变量 "%s" 和 "%s" 的追加在节点序上逐次相邻（各 %d 次，%s），应合并为单个 MATLAB.DataTypes.InsertiveTable', ...
                    pair.varA, pair.varB, pair.count, pair.appendKind)}; %#ok<AGROW>
            end
        end
    end
end

issues = table(issuesBuilder);
end

% -------------------------------------------------------------------------
function scopes = iMakeScriptScope(Tree)
rootPosL = 1;
rootPosR = inf;
try
    % 以全树范围作为脚本作用域
    allIds = Tree.mtfind('Kind', 'ID').indices;
    if ~isempty(allIds)
        firstNode = Tree.select(allIds(1));
        rootPosL = lefttreepos(firstNode);
        rootPosR = righttreepos(firstNode);
        for i = 2:numel(allIds)
            nd = Tree.select(allIds(i));
            rootPosL = min(rootPosL, lefttreepos(nd));
            rootPosR = max(rootPosR, righttreepos(nd));
        end
    end
catch
end
scopes = struct('leftPos', rootPosL, 'rightPos', rootPosR, 'name', "<script>");
end

% -------------------------------------------------------------------------
function scopes = iMakeFunctionScopes(Tree, fnIdx)
scopes = repmat(struct('leftPos', 0, 'rightPos', 0, 'name', ""), numel(fnIdx), 1);
for i = 1:numel(fnIdx)
    nd = Tree.select(fnIdx(i));
    scopes(i).leftPos = lefttreepos(nd);
    scopes(i).rightPos = righttreepos(nd);
    try
        scopes(i).name = string(nd.Fname.string);
    catch
        scopes(i).name = "<function>";
    end
end
end

% -------------------------------------------------------------------------
function vars = iCollectBuilderVarsInScope(Tree, scope)
vars = strings(0, 1);
constructorMap = configureDictionary('string', 'string');

ix = Tree.mtfind('Kind', 'EQUALS').indices;
for i = 1:numel(ix)
    nd = Tree.select(ix(i));
    if ~iInScope(nd, scope)
        continue;
    end
    lhs = Left(nd);
    rhs = Right(nd);
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'ID')
        continue;
    end
    ctor = iNormalizeCtor(iNodeText(rhs));
    if strlength(ctor) == 0
        continue;
    end

    v = string(lhs.string);
    constructorMap(char(v)) = ctor;
end

ks = constructorMap.keys;
for k = 1:numel(ks)
    vars(end+1, 1) = string(ks(k)); %#ok<AGROW>
end
end

% -------------------------------------------------------------------------
function events = iCollectAppendEventsInScope(Tree, scope, vars)
events = repmat(struct('var', "", 'appendKind', "", 'line', 0, 'pos', 0, 'eventOrder', 0), 0, 1);
varSet = configureDictionary('string', 'logical');
for i = 1:numel(vars)
    varSet(char(vars(i))) = true;
end

ix = Tree.mtfind('Kind', 'SUBSCR').indices;
if isempty(ix)
    return;
end

pos = zeros(numel(ix), 1);
for i = 1:numel(ix)
    pos(i) = lefttreepos(Tree.select(ix(i)));
end
[~, order] = sort(pos);

for oi = 1:numel(order)
    nd = Tree.select(ix(order(oi)));
    if ~iInScope(nd, scope)
        continue;
    end

    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(char(lhs.kind), 'DOT')
        continue;
    end

    obj = Left(lhs);
    meth = Right(lhs);
    if count(obj) ~= 1 || ~strcmp(char(obj.kind), 'ID')
        continue;
    end

    varName = string(obj.string);
    if ~isKey(varSet, char(varName))
        continue;
    end

    method = iNodeText(meth);
    if strcmpi(method, "Append")
        kind = "Append";
    elseif strcmpi(method, "PushBack")
        kind = "PushBack";
    else
        continue;
    end

    e.var = varName;
    e.appendKind = kind;
    e.line = double(nd.lineno);
    e.pos = lefttreepos(nd);
    e.eventOrder = 0;
    events(end+1) = e; %#ok<AGROW>
end
end

% -------------------------------------------------------------------------
function pair = iBuildPair(events, varA, varB)
rowsA = events(strcmp(string({events.var}), varA));
rowsB = events(strcmp(string({events.var}), varB));

pair.varA = varA;
pair.varB = varB;
pair.count = min(numel(rowsA), numel(rowsB));
pair.firstLine = 0;
pair.appendKind = "";
pair.ordersA = zeros(0, 1);
pair.ordersB = zeros(0, 1);
pair.kindsA = strings(0, 1);
pair.kindsB = strings(0, 1);

if isempty(rowsA) || isempty(rowsB)
    return;
end

pair.firstLine = min([rowsA(1).line, rowsB(1).line]);
pair.ordersA = [rowsA.eventOrder].';
pair.ordersB = [rowsB.eventOrder].';
pair.kindsA = string({rowsA.appendKind}).';
pair.kindsB = string({rowsB.appendKind}).';

if all(pair.kindsA == "Append") && all(pair.kindsB == "Append")
    pair.appendKind = "Append";
elseif all(pair.kindsA == "PushBack") && all(pair.kindsB == "PushBack")
    pair.appendKind = "PushBack";
else
    pair.appendKind = "Mixed";
end
end

% -------------------------------------------------------------------------
function tf = iIsSynchronousPair(pair)
tf = false;

if pair.count < 2
    return;
end
if numel(pair.ordersA) ~= numel(pair.ordersB)
    return;
end
if strlength(pair.appendKind) == 0 || pair.appendKind == "Mixed"
    return;
end

for i = 1:numel(pair.ordersA)
    if abs(pair.ordersA(i) - pair.ordersB(i)) ~= 1
        return;
    end
end

tf = true;
end

% -------------------------------------------------------------------------
function tf = iInScope(node, scope)
tf = lefttreepos(node) >= scope.leftPos && righttreepos(node) <= scope.rightPos;
end

% -------------------------------------------------------------------------
function ctor = iNormalizeCtor(fnText)
ctor = "";
t = lower(strtrim(string(fnText)));
     if contains(t, "matlab.datatypes.arraybuilder(")
    ctor = "ArrayBuilder";
     elseif contains(t, "matlab.containers.vector(")
    ctor = "Vector";
end
end

% -------------------------------------------------------------------------
function s = iNodeText(node)
s = "";
if count(node) == 0
    return;
end
try
    s = strtrim(string(node.tree2str));
catch
    try
        s = strtrim(string(node.string));
    catch
        s = "";
    end
end
end
