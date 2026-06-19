function assignments = collectAssignments(FullTree, fnNode, detectSelfRef)
%COLLECTASSIGNMENTS 提取函数内的简单赋值（左值为单个 ID）。
% assignments = table(line, var, isSelfRef, eqIdx)
% detectSelfRef=true 时递归检查 RHS 是否引用同名变量。

if nargin < 4
    detectSelfRef = false;
end

builder = MATLAB.DataTypes.InsertiveTable();
ix = FullTree.mtfind('Kind', 'EQUALS').indices;
if isempty(ix)
    assignments = table(builder);
    return;
end

fnLeft = lefttreepos(fnNode);
fnRight = righttreepos(fnNode);

for i = 1:numel(ix)
    nd = FullTree.select(ix(i));
    if lefttreepos(nd) < fnLeft || righttreepos(nd) > fnRight
        continue;
    end

    lhs = Left(nd);
    if count(lhs) ~= 1 || ~strcmp(lhs.kind, 'ID')
        continue;
    end

    varName = lhs.string;
    if strlength(varName) == 0
        continue;
    end

    isSelfRef = false;
    if detectSelfRef
        isSelfRef = iTreeContainsSelfRef(Right(nd), FullTree, varName);
        if ~isSelfRef
            isSelfRef = iIsLoopControlFlagAssign(FullTree, nd, varName);
        end
    end

    builder(end+1, {'line','var','isSelfRef','eqIdx'}) = ...
        {double(nd.lineno), varName, isSelfRef, ix(i)};
end

assignments = table(builder);
end

% -------------------------------------------------------------------------
function tf = iTreeContainsSelfRef(node, FullTree, varName)
tf = false;
if count(node) == 0
    return;
end

k = node.kind;
if k == "ID"
    tf = node.string == varName;
    return;
end

if ismember(k, ["NOT","UMINUS","UPLUS","TRANS","DOTTRANS"])
    if count(Arg(node)) > 0
        tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
    end
    return;
end

if ismember(k, ["PLUS","MINUS","MUL","DIV","LDIV","DOTMUL","DOTDIV","DOTLDIV", ...
        "EXP","DOTEXP","EQ","NE","LT","GT","LE","GE","AND","OR","SHORTAND","SHORTOR", ...
        "COLON","DOT"])
    if iTreeContainsSelfRef(Left(node), FullTree, varName)
        tf = true;
        return;
    end
    if count(Right(node)) > 0
        tf = iTreeContainsSelfRef(Right(node), FullTree, varName);
    end
    return;
end

if k == "SUBSCR"
    if count(Left(node)) > 0 && iTreeContainsSelfRef(Left(node), FullTree, varName)
        tf = true;
        return;
    end
    if count(Right(node)) > 0
        tf = iTreeContainsSelfRef(Right(node), FullTree, varName);
    end
    return;
end

if k == "CALL"
    if count(Right(node)) > 0
        tf = iTreeContainsSelfRef(Right(node), FullTree, varName);
    end
    return;
end

if ismember(k, ["EXPR","PARENS","LB"])
    if count(Arg(node)) > 0
        tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
    end
    return;
end

if ismember(k, ["ROW","CELL"])
    child = Arg(node);
    while count(child) > 0
        if iTreeContainsSelfRef(child, FullTree, varName)
            tf = true;
            return;
        end
        try
            child = Next(child);
        catch
            break;
        end
    end
    return;
end

if (count(Left(node)) > 0 && iTreeContainsSelfRef(Left(node), FullTree, varName)) ...
        || (count(Right(node)) > 0 && iTreeContainsSelfRef(Right(node), FullTree, varName))
    tf = true;
    return;
end
if count(Arg(node)) > 0
    tf = iTreeContainsSelfRef(Arg(node), FullTree, varName);
end
end

% -------------------------------------------------------------------------
function tf = iIsLoopControlFlagAssign(FullTree, p, varName)
tf = false;
p = Parent(p);
while count(p) > 0
    if p.kind == "WHILE"
        condIDs = List(Left(p)).mtfind('Kind', 'ID');
        if count(condIDs) == 0
            return;
        end
        cix = condIDs.indices;
        for ki = 1:numel(cix)
            if string(FullTree.select(cix(ki)).string) == varName
                tf = true;
                return;
            end
        end
        return;
    end
    p = Parent(p);
end
end

